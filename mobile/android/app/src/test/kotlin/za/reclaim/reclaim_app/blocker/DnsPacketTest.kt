package za.reclaim.reclaim_app.blocker

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DnsPacketTest {
    /** A DNS query for [name] (type A, RD set) with id 0x1234. */
    private fun dnsQuery(name: String): ByteArray {
        val question = name.split('.').flatMap { label -> listOf(label.length.toByte()) + label.toByteArray().toList() } +
            listOf<Byte>(0, 0, 1, 0, 1)
        // EDNS OPT record in the additional section, as real resolvers send.
        val opt = listOf<Byte>(0, 0, 41, 0x10, 0, 0, 0, 0, 0, 0, 0)
        return (listOf<Byte>(0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 1) + question + opt).toByteArray()
    }

    /** Wraps [dns] in IPv4/UDP from 10.111.222.1:40000 to 10.111.222.2:53. */
    private fun ipPacket(dns: ByteArray, protocol: Int = 17, destinationPort: Int = 53): ByteArray {
        val total = 28 + dns.size
        val packet = ByteArray(total)
        packet[0] = 0x45
        packet[2] = (total shr 8).toByte(); packet[3] = total.toByte()
        packet[8] = 64; packet[9] = protocol.toByte()
        byteArrayOf(10, 111, 222.toByte(), 1).copyInto(packet, 12)
        byteArrayOf(10, 111, 222.toByte(), 2).copyInto(packet, 16)
        packet[20] = (40000 shr 8).toByte(); packet[21] = 40000.toByte()
        packet[22] = (destinationPort shr 8).toByte(); packet[23] = destinationPort.toByte()
        packet[24] = ((8 + dns.size) shr 8).toByte(); packet[25] = (8 + dns.size).toByte()
        dns.copyInto(packet, 28)
        return packet
    }

    @Test
    fun parsesTheQueriedNameInLowerCase() {
        val query = DnsPacket.parseQuery(ipPacket(dnsQuery("Sport.Betway.co.za")))!!
        assertEquals("sport.betway.co.za", query.name)
        assertEquals(40000, query.sourcePort)
        assertEquals(53, query.destinationPort)
    }

    @Test
    fun ignoresNonDnsTraffic() {
        assertNull(DnsPacket.parseQuery(ipPacket(dnsQuery("a.com"), protocol = 6)))
        assertNull(DnsPacket.parseQuery(ipPacket(dnsQuery("a.com"), destinationPort = 443)))
        assertNull(DnsPacket.parseQuery(ByteArray(10)))
    }

    @Test
    fun ignoresResponses() {
        val response = dnsQuery("a.com").also { it[2] = (it[2].toInt() or 0x80).toByte() }
        assertNull(DnsPacket.parseQuery(ipPacket(response)))
    }

    @Test
    fun nxdomainKeepsIdAndQuestionAndDropsOtherRecords() {
        val query = dnsQuery("betway.co.za")
        val answer = DnsPacket.nxdomainFor(query)
        assertEquals(0x12, answer[0].toInt()); assertEquals(0x34, answer[1].toInt())
        assertEquals(0x81, answer[2].toInt() and 0xFF) // response, recursion desired
        assertEquals(0x83, answer[3].toInt() and 0xFF) // recursion available, NXDOMAIN
        assertEquals(1, answer[5].toInt()) // one question
        assertEquals(0, answer[11].toInt()) // no additional records
        assertEquals(query.size - 11, answer.size) // the OPT record is gone
        assertEquals("betway.co.za", DnsPacket.readName(answer, 12))
    }

    @Test
    fun replySwapsAddressesAndPortsWithAValidChecksum() {
        val query = DnsPacket.parseQuery(ipPacket(dnsQuery("a.com")))!!
        val payload = byteArrayOf(1, 2, 3)
        val reply = DnsPacket.buildReply(query, payload)

        assertArrayEquals(byteArrayOf(10, 111, 222.toByte(), 2), reply.copyOfRange(12, 16))
        assertArrayEquals(byteArrayOf(10, 111, 222.toByte(), 1), reply.copyOfRange(16, 20))
        assertEquals(53, ((reply[20].toInt() and 0xFF) shl 8) or (reply[21].toInt() and 0xFF))
        assertEquals(40000, ((reply[22].toInt() and 0xFF) shl 8) or (reply[23].toInt() and 0xFF))
        assertEquals(31, reply.size)
        assertEquals(0, DnsPacket.checksum(reply, 0, 20)) // a correct header sums to zero
        assertArrayEquals(payload, reply.copyOfRange(28, 31))
    }
}

class DomainMatcherTest {
    private val matcher = DomainMatcher(listOf("betway.co.za", "Stake.com.", "www.bet365.com", ""))

    @Test
    fun matchesTheDomainAndItsSubdomains() {
        assertEquals("betway.co.za", matcher.match("betway.co.za"))
        assertEquals("betway.co.za", matcher.match("live.sport.BETWAY.co.za"))
        assertEquals("stake.com", matcher.match("stake.com"))
        assertEquals("bet365.com", matcher.match("www.bet365.com"))
        assertEquals(3, matcher.size)
    }

    @Test
    fun doesNotMatchLookalikesOrParents() {
        assertNull(matcher.match("notbetway.co.za"))
        assertNull(matcher.match("co.za"))
        assertNull(matcher.match("example.com"))
    }
}
