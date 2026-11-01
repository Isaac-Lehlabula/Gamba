package za.reclaim.reclaim_app.blocker

/**
 * Just enough IPv4, UDP and DNS (RFC 791, 768, 1035) to filter DNS lookups: read the name a
 * query asks for, answer blocked names with NXDOMAIN, and wrap upstream answers back into
 * packets for the tunnel. Pure functions with no Android dependencies, so they are unit-tested
 * on the JVM.
 */
object DnsPacket {
    private const val IPV4_HEADER = 20
    private const val UDP_HEADER = 8
    private const val DNS_HEADER = 12
    private const val PROTOCOL_UDP = 17
    const val DNS_PORT = 53

    /** A DNS query captured from the tunnel. */
    class Query(
        val sourceAddress: ByteArray,
        val destinationAddress: ByteArray,
        val sourcePort: Int,
        val destinationPort: Int,
        /** The DNS message itself (the UDP payload). */
        val dns: ByteArray,
        /** Lower-case name being looked up, without a trailing dot. */
        val name: String,
    )

    /** Parses an IPv4/UDP packet carrying a DNS query to port 53; null for anything else. */
    fun parseQuery(packet: ByteArray, length: Int = packet.size): Query? {
        if (length < IPV4_HEADER + UDP_HEADER + DNS_HEADER) return null
        val version = (packet[0].toInt() shr 4) and 0xF
        val ihl = (packet[0].toInt() and 0xF) * 4
        if (version != 4 || ihl < IPV4_HEADER || length < ihl + UDP_HEADER + DNS_HEADER) return null
        if (packet[9].toInt() and 0xFF != PROTOCOL_UDP) return null
        // Ignore fragments: a DNS query fits in one packet.
        val fragment = u16(packet, 6)
        if (fragment and 0x3FFF != 0) return null

        val udp = ihl
        val destinationPort = u16(packet, udp + 2)
        if (destinationPort != DNS_PORT) return null
        val udpLength = u16(packet, udp + 4)
        val dnsLength = minOf(udpLength - UDP_HEADER, length - udp - UDP_HEADER)
        if (dnsLength < DNS_HEADER) return null
        val dns = packet.copyOfRange(udp + UDP_HEADER, udp + UDP_HEADER + dnsLength)

        val isQuery = (dns[2].toInt() and 0x80) == 0
        if (!isQuery || u16(dns, 4) < 1) return null
        val name = readName(dns, DNS_HEADER) ?: return null

        return Query(
            sourceAddress = packet.copyOfRange(12, 16),
            destinationAddress = packet.copyOfRange(16, 20),
            sourcePort = u16(packet, udp),
            destinationPort = destinationPort,
            dns = dns,
            name = name,
        )
    }

    /**
     * A "no such domain" answer to [query]'s DNS message: same id and question, response flag
     * set, no records. Browsers and apps fail the lookup immediately rather than timing out.
     */
    fun nxdomainFor(query: ByteArray): ByteArray {
        val questionEnd = questionEnd(query) ?: return ByteArray(0)
        val response = query.copyOf(questionEnd)
        val recursionDesired = query[2].toInt() and 0x01
        val opcode = query[2].toInt() and 0x78
        response[2] = (0x80 or opcode or recursionDesired).toByte() // QR=1, same opcode, RD copied
        response[3] = (0x80 or 0x03).toByte() // RA=1, RCODE=3 (NXDOMAIN)
        // QDCOUNT stays 1; no answer, authority or additional records.
        response[4] = 0; response[5] = 1
        for (i in 6 until 12) response[i] = 0
        return response
    }

    /** Wraps a DNS [payload] as the IPv4/UDP reply to [query], swapping its addresses and ports. */
    fun buildReply(query: Query, payload: ByteArray): ByteArray {
        val total = IPV4_HEADER + UDP_HEADER + payload.size
        val packet = ByteArray(total)
        packet[0] = 0x45 // IPv4, 20-byte header
        put16(packet, 2, total)
        put16(packet, 6, 0x4000) // don't fragment
        packet[8] = 64 // TTL
        packet[9] = PROTOCOL_UDP.toByte()
        query.destinationAddress.copyInto(packet, 12)
        query.sourceAddress.copyInto(packet, 16)
        put16(packet, 10, checksum(packet, 0, IPV4_HEADER))

        put16(packet, IPV4_HEADER, query.destinationPort)
        put16(packet, IPV4_HEADER + 2, query.sourcePort)
        put16(packet, IPV4_HEADER + 4, UDP_HEADER + payload.size)
        // A zero UDP checksum means "not computed", which IPv4 allows.
        payload.copyInto(packet, IPV4_HEADER + UDP_HEADER)
        return packet
    }

    /** Reads an uncompressed name (queries never use compression) starting at [offset]. */
    internal fun readName(dns: ByteArray, offset: Int): String? {
        val labels = mutableListOf<String>()
        var i = offset
        while (true) {
            if (i >= dns.size) return null
            val len = dns[i].toInt() and 0xFF
            if (len == 0) break
            if (len and 0xC0 != 0 || i + 1 + len > dns.size || len > 63) return null
            labels += String(dns, i + 1, len, Charsets.US_ASCII).lowercase()
            i += 1 + len
        }
        val name = labels.joinToString(".")
        return if (name.isEmpty() || name.length > 253) null else name
    }

    /** Where the first question ends (after QNAME, QTYPE and QCLASS). */
    private fun questionEnd(dns: ByteArray): Int? {
        var i = DNS_HEADER
        while (i < dns.size) {
            val len = dns[i].toInt() and 0xFF
            if (len == 0) return (i + 1 + 4).takeIf { it <= dns.size }
            if (len and 0xC0 != 0) return null
            i += 1 + len
        }
        return null
    }

    internal fun checksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0L
        var i = offset
        while (i < offset + length - 1) {
            sum += u16(data, i)
            i += 2
        }
        if (length % 2 == 1) sum += (data[offset + length - 1].toInt() and 0xFF) shl 8
        while (sum shr 16 != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv().toInt() and 0xFFFF
    }

    private fun u16(data: ByteArray, offset: Int) =
        ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)

    private fun put16(data: ByteArray, offset: Int, value: Int) {
        data[offset] = (value shr 8).toByte()
        data[offset + 1] = value.toByte()
    }
}
