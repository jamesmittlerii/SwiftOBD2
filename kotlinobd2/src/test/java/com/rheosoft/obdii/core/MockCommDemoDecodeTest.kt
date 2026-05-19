package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

/**
 * Mirrors [com.rheosoft.obdii.core.ObdConnectionManager] response extraction + decode,
 * not [Parser.parseHexBytes] (which takes a different strip path).
 */
class MockCommDemoDecodeTest {

    @Test
    fun mockRpmAndControlVoltageDecodeWithinRealisticRanges() = runBlocking {
        val mock = MockComm()
        mock.connectAsync(timeoutMs = 1)

        val rpm = decodeMode1(mock, "010C")
        val volts = decodeMode1(mock, "0142")

        assertIs<DecodeResult.Measurement>(rpm)
        assertIs<DecodeResult.Measurement>(volts)

        val rpmValue = (rpm as DecodeResult.Measurement).value.value
        val voltValue = (volts as DecodeResult.Measurement).value.value

        val rpmLines = mock.sendCommand("010C")
        val voltLines = mock.sendCommand("0142")
        assertTrue(
            rpmValue in 800.0..8000.0,
            "RPM should be 800–8000 in demo; got $rpmValue (lines=$rpmLines)",
        )
        assertTrue(
            voltValue in 12.0..15.0,
            "Control module voltage should be ~12–15 V in demo; got $voltValue (lines=$voltLines)",
        )
    }

    @Test
    fun parseHexBytesPathDiffersFromConnectionManagerPathForRpm() = runBlocking {
        val mock = MockComm()
        val lines = mock.sendCommand("010C")

        val viaParseHex = Parser.parseHexBytes(lines)
        val viaConnectionManager = responseBytesLikeConnectionManager(lines)

        val fromHex = OBDCommand.Mode1("0C").properties.decode(viaParseHex)
        val fromConn = OBDCommand.Mode1("0C").properties.decode(viaConnectionManager)

        assertIs<DecodeResult.Measurement>(fromHex)
        assertIs<DecodeResult.Measurement>(fromConn)

        val rpmHex = (fromHex as DecodeResult.Measurement).value.value
        val rpmConn = (fromConn as DecodeResult.Measurement).value.value

        assertTrue(rpmHex in 800.0..8000.0, "parseHexBytes path RPM=$rpmHex")
        assertEquals(
            rpmHex,
            rpmConn,
            "ObdConnectionManager-style bytes should match parseHexBytes decode; " +
                "hex=$viaParseHex conn=$viaConnectionManager",
        )
    }

    private suspend fun decodeMode1(mock: MockComm, command: String): DecodeResult {
        val pid = command.takeLast(2)
        val bytes = responseBytesLikeConnectionManager(mock.sendCommand(command))
        return OBDCommand.Mode1(pid).properties.decode(bytes)
    }

    private fun responseBytesLikeConnectionManager(lines: List<String>): List<Int> {
        val frames = Parser.parseFrames(lines)
        if (frames.isEmpty()) return emptyList()

        val firstFrame = frames.firstOrNull { it.type == FrameType.FirstFrame }
        if (firstFrame != null) {
            return Parser.parseMessages(frames).firstOrNull()?.data ?: emptyList()
        }

        val singleFrame = frames.firstOrNull { it.type == FrameType.SingleFrame } ?: return emptyList()
        val hasCanHeader = singleFrame.raw.substringBefore(' ').length == 3
        return if (hasCanHeader) {
            singleFrame.data.drop(1).take(singleFrame.dataLen ?: 0)
        } else {
            singleFrame.data
        }
    }
}
