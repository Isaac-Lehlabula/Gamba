package za.reclaim.reclaim_app.blocker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import za.reclaim.reclaim_app.MainActivity
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On-device DNS filtering (see docs/BLOCKING.md). The tunnel only routes DNS: the VPN tells
 * Android to use a private DNS address that exists only inside the tunnel, so every lookup
 * arrives here. Blocked names get NXDOMAIN; everything else is forwarded to the real network's
 * DNS servers and the answer relayed back. No traffic leaves the phone for Reclaim's servers.
 */
class ReclaimVpnService : VpnService() {
    private val running = AtomicBoolean(false)
    private var tunnel: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private val forwarders = Executors.newFixedThreadPool(4)
    @Volatile private var matcher = DomainMatcher(emptyList())
    @Volatile private var upstreamCache: Pair<Long, List<InetAddress>>? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand action=${intent?.action} running=${running.get()}")
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                return START_NOT_STICKY
            }
            ACTION_RELOAD -> {
                if (!active) {
                    // Nothing to reload; don't leave a service running without a tunnel.
                    stopSelf()
                    return START_NOT_STICKY
                }
                matcher = loadMatcher(this)
                return START_STICKY
            }
        }
        try {
            startForegroundNotice()
            matcher = loadMatcher(this)
            Log.i(TAG, "Loaded ${matcher.size} blocked domains")
            if (running.compareAndSet(false, true)) startTunnel()
        } catch (e: Exception) {
            Log.e(TAG, "Couldn't start protection", e)
            stopTunnel()
        }
        return START_STICKY
    }

    override fun onRevoke() {
        Log.i(TAG, "onRevoke")
        // The user turned the VPN off in system settings, or another VPN app took over.
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopTunnel()
        forwarders.shutdownNow()
        super.onDestroy()
    }

    private fun startTunnel() {
        val fd = Builder()
            .setSession("Reclaim protection")
            .addAddress(TUNNEL_ADDRESS, 32)
            .addDnsServer(TUNNEL_DNS)
            // Only DNS to the in-tunnel address is routed here; other traffic is untouched.
            .addRoute(TUNNEL_DNS, 32)
            .addDisallowedApplication(packageName)
            .setBlocking(true)
            .setConfigureIntent(openAppIntent())
            .establish()
        Log.i(TAG, "establish -> ${fd != null}")
        if (fd == null) {
            // Permission was never granted (or was revoked); nothing to run.
            running.set(false)
            stopSelf()
            return
        }
        tunnel = fd
        active = true
        reader = Thread({ readLoop(fd) }, "reclaim-dns").apply { start() }
    }

    private fun readLoop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val output = FileOutputStream(fd.fileDescriptor)
        val buffer = ByteArray(32767)
        try {
            while (running.get()) {
                val length = input.read(buffer)
                if (length <= 0) continue
                val query = DnsPacket.parseQuery(buffer, length) ?: continue
                val blockedBy = matcher.match(query.name)
                if (blockedBy != null) {
                    recordBlocked(this, blockedBy)
                    write(output, DnsPacket.buildReply(query, DnsPacket.nxdomainFor(query.dns)))
                } else {
                    forwarders.execute { forward(query, output) }
                }
            }
        } catch (e: Exception) {
            if (running.get()) Log.w(TAG, "DNS loop stopped", e)
        }
    }

    private fun forward(query: DnsPacket.Query, output: FileOutputStream) {
        val servers = try {
            upstreamServers()
        } catch (e: Exception) {
            Log.w(TAG, "No upstream DNS", e)
            return
        }
        for (server in servers) {
            try {
                DatagramSocket().use { socket ->
                    // Keep the forwarded lookup out of our own tunnel.
                    protect(socket)
                    socket.soTimeout = 5000
                    socket.send(DatagramPacket(query.dns, query.dns.size, server, DnsPacket.DNS_PORT))
                    val response = ByteArray(4096)
                    val packet = DatagramPacket(response, response.size)
                    socket.receive(packet)
                    write(output, DnsPacket.buildReply(query, response.copyOf(packet.length)))
                    return
                }
            } catch (e: Exception) {
                Log.d(TAG, "Upstream DNS $server failed: ${e.javaClass.simpleName}")
            }
        }
    }

    /**
     * The DNS servers of the real (non-VPN) network, refreshed every 30 seconds. Falls back to
     * public resolvers if they can't be found; this runs on worker threads, where an uncaught
     * exception would kill the app and the tunnel with it.
     */
    private fun upstreamServers(): List<InetAddress> {
        val now = System.currentTimeMillis()
        upstreamCache?.let { (at, servers) -> if (now - at < 30_000 && servers.isNotEmpty()) return servers }
        val servers = try {
            val cm = getSystemService(ConnectivityManager::class.java)
            @Suppress("DEPRECATION") // allNetworks is the only way to find the underlying network from a VPN.
            cm.allNetworks
                .filter { network ->
                    val caps = cm.getNetworkCapabilities(network)
                    caps != null && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                }
                .flatMap { cm.getLinkProperties(it)?.dnsServers.orEmpty() }
                .filter { it.hostAddress != TUNNEL_DNS }
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't read the network's DNS servers", e)
            emptyList()
        }.ifEmpty { FALLBACK_DNS.map(InetAddress::getByName) }
        upstreamCache = now to servers
        return servers
    }

    @Synchronized
    private fun write(output: FileOutputStream, packet: ByteArray) {
        try {
            output.write(packet)
        } catch (e: Exception) {
            Log.d(TAG, "Tunnel write failed: ${e.javaClass.simpleName}")
        }
    }

    private fun stopTunnel() {
        Log.i(TAG, "stopTunnel running=${running.get()} tunnel=${tunnel != null}")
        running.set(false)
        active = false
        try {
            tunnel?.close()
        } catch (_: Exception) {
        }
        tunnel = null
        reader?.interrupt()
        reader = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startForegroundNotice() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Protection", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while Reclaim is filtering gambling sites"
            },
        )
        // Deliberately discreet wording: the notification can be seen by anyone glancing at the phone.
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Reclaim protection is on")
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    companion object {
        private const val TAG = "ReclaimVpn"
        const val ACTION_START = "za.reclaim.blocker.START"
        const val ACTION_STOP = "za.reclaim.blocker.STOP"
        const val ACTION_RELOAD = "za.reclaim.blocker.RELOAD"

        private const val CHANNEL_ID = "protection"
        private const val NOTIFICATION_ID = 1
        private const val TUNNEL_ADDRESS = "10.111.222.1"
        private const val TUNNEL_DNS = "10.111.222.2"
        private val FALLBACK_DNS = listOf("1.1.1.1", "8.8.8.8")

        const val BLOCKLIST_FILE = "blocklist.txt"
        private const val LOG_FILE = "blocked_log.txt"
        private const val MAX_LOG_LINES = 500

        /**
         * Whether the tunnel is up right now. Kept in memory, not in preferences, so it can't
         * outlive a crash and report protection that isn't there.
         */
        @Volatile
        var active = false
            private set

        /** One domain per line, written by the Flutter side whenever the list changes. */
        fun loadMatcher(context: Context): DomainMatcher {
            val file = File(context.filesDir, BLOCKLIST_FILE)
            return DomainMatcher(if (file.exists()) file.readLines() else emptyList())
        }

        /**
         * Keeps a short local log of blocked lookups (time and the listed domain only) so the app
         * can show that protection is working. It never leaves the phone.
         */
        @Synchronized
        fun recordBlocked(context: Context, domain: String) {
            val file = File(context.filesDir, LOG_FILE)
            file.appendText("${System.currentTimeMillis()}\t$domain\n")
            val lines = file.readLines()
            if (lines.size > MAX_LOG_LINES) file.writeText(lines.takeLast(MAX_LOG_LINES).joinToString("\n", postfix = "\n"))
        }

        @Synchronized
        fun readBlockedLog(context: Context): List<String> {
            val file = File(context.filesDir, LOG_FILE)
            return if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList()
        }

        @Synchronized
        fun clearBlockedLog(context: Context) {
            File(context.filesDir, LOG_FILE).delete()
        }
    }
}
