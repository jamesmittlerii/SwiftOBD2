package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.protocols.*
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class ProtocolTest {

    private val can11Protocols = listOf(
        Iso157654Can11Bit500K(),
        Iso157654Can11Bit250K()
    )

    private val legacyProtocols = listOf(
        SaeJ1850Pwm(),
        SaeJ1850Vpw(),
        Iso91412(),
        Iso142304Kwp5Baud(),
        Iso142304KwpFast()
    )

    @Test
    fun testCanSingleFrame() {
        for (protocol in can11Protocols) {
            val response = protocol.parse(listOf("7E8 06 41 00 00 01 02 03"))
            assertEquals(1, response.size)
            assertNotNull(response[0].data)
            assertEquals(listOf(0x00, 0x00, 0x01, 0x02, 0x03), response[0].data)

            // Minimum valid length
            val minValid = protocol.parse(listOf("7E8 01 41"))
            assertEquals(1, minValid.size)

            // Too short
            val tooShort = protocol.parse(listOf("7E8 01"))
            assertEquals(0, tooShort.size)
        }
    }

    @Test
    fun testLegacySingleFrame() {
        for (protocol in legacyProtocols) {
            // Minimum valid length
            // "48 6B 10 41 00 FF" -> 48 6B 10 is header, 41 is mode, 00 is PID, FF is checksum
            // Our parser strips header and checksum, leaving [41, 00]. 
            // parseMessages drops the first byte (Mode 41), leaving [0x00].
            val minValid = protocol.parse(listOf("48 6B 10 41 00 FF"))
            assertEquals(1, minValid.size)
            assertEquals(listOf(0x00), minValid[0].data)

            // Maximum valid length
            val maxValid = protocol.parse(listOf("48 6B 10 41 00 00 01 02 03 04 FF"))
            assertEquals(1, maxValid.size)
            assertEquals(listOf(0x00, 0x00, 0x01, 0x02, 0x03, 0x04), maxValid[0].data)

            // Too short
            val tooShort = protocol.parse(listOf("48 6B 10 41"))
            assertEquals(0, tooShort.size)
        }
    }
}
