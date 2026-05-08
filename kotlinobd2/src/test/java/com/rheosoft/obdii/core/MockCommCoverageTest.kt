package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MockCommCoverageTest {
    private fun MockComm.setElapsedSeconds(seconds: Double) {
        val field = MockComm::class.java.getDeclaredField("startAt")
        field.isAccessible = true
        field.setLong(this, System.currentTimeMillis() - (seconds * 1000).toLong())
    }

    private fun List<String>.payloadBytes(): List<Int> {
        return single()
            .split(" ")
            .drop(1)
            .filter { it.matches(Regex("[0-9A-F]{2}")) }
            .map { it.toInt(16) }
    }

    @Test
    fun connectionLifecycleEmitsStateAndDelegateCallbacks() = runBlocking {
        val mock = MockComm()
        val delegateStates = mutableListOf<AdapterConnectionState>()
        mock.obdDelegate = object : OBDServiceDelegate {
            override fun connectionStateChanged(state: AdapterConnectionState) {
                delegateStates += state
            }
        }

        mock.connectAsync(timeoutMs = 1)
        assertEquals(AdapterConnectionState.connectedToAdapter, mock.connectionState.value)

        mock.disconnectPeripheral()
        assertEquals(AdapterConnectionState.disconnected, mock.connectionState.value)
        assertTrue(delegateStates.contains(AdapterConnectionState.connecting))
        assertTrue(delegateStates.contains(AdapterConnectionState.connectedToAdapter))
        assertTrue(delegateStates.contains(AdapterConnectionState.disconnected))
    }

    @Test
    fun connectionLifecycleWorksWithoutDelegate() = runBlocking {
        val mock = MockComm()

        mock.connectAsync(timeoutMs = 1)
        assertEquals(AdapterConnectionState.connectedToAdapter, mock.connectionState.value)

        mock.disconnectPeripheral()
        assertEquals(AdapterConnectionState.disconnected, mock.connectionState.value)
    }

    @Test
    fun atCommandsControlEchoAndHeaders() = runBlocking {
        val mock = MockComm()

        assertEquals(listOf("ELM327 v1.5"), mock.sendCommand("ATZ"))
        assertEquals(listOf("OK"), mock.sendCommand("ATL0"))
        assertEquals(listOf("OK"), mock.sendCommand("ATS0"))
        assertEquals(listOf("OK"), mock.sendCommand("ATSP0"))
        assertEquals(listOf("OK"), mock.sendCommand("ATAT1"))
        assertEquals(listOf("OK"), mock.sendCommand("ATAL"))
        assertEquals(listOf("OK"), mock.sendCommand("ATST64"))

        assertEquals(listOf("ATE1", "OK"), mock.sendCommand("ATE1"))
        assertEquals(listOf("ATH0", "OK"), mock.sendCommand("ATH0"))
        assertEquals("010C", mock.sendCommand("010C").first())
        assertFalse(mock.sendCommand("010C").last().startsWith("7E8"))

        assertEquals(listOf("OK"), mock.sendCommand("ATE0"))
        assertEquals(listOf("OK"), mock.sendCommand("ATH1"))
        assertTrue(mock.sendCommand("010C").single().startsWith("7E8"))
    }

    @Test
    fun supportAndInfoModesReturnExpectedFrames() = runBlocking {
        val mock = MockComm()

        assertTrue(mock.sendCommand("0100").single().contains("41 00 FF FF FF FF"))
        assertTrue(mock.sendCommand("0120").single().contains("41 20 FF FF FF FF"))
        assertTrue(mock.sendCommand("0140").single().contains("41 40 FF FF FF FE"))

        assertEquals(3, mock.sendCommand("03").size)
        assertTrue(mock.sendCommand("03").first().contains("43 07"))

        assertTrue(mock.sendCommand("0600").single().contains("46 00"))
        assertTrue(mock.sendCommand("0620").single().contains("46 20"))
        assertTrue(mock.sendCommand("0640").single().contains("46 40"))
        assertTrue(mock.sendCommand("0660").single().contains("46 60"))
        assertTrue(mock.sendCommand("0680").single().contains("46 80"))
        assertTrue(mock.sendCommand("06A0").single().contains("46 A0"))
        assertEquals(listOf("NO DATA"), mock.sendCommand("06FF"))

        assertTrue(mock.sendCommand("0900").single().contains("49 00"))
        assertEquals(3, mock.sendCommand("0902").size)
        assertEquals(listOf("NO DATA"), mock.sendCommand("09FF"))

        assertTrue(mock.sendCommand("221144").single().contains("62 11 44"))
        assertTrue(mock.sendCommand("221470").single().contains("62 14 70"))
        assertTrue(mock.sendCommand("221940").single().contains("62 19 40"))
        assertTrue(mock.sendCommand("221154").single().contains("62 11 54"))
        assertEquals(listOf("NO DATA"), mock.sendCommand("22FFFF"))
        assertEquals(listOf("NO DATA"), mock.sendCommand("FFFF"))
        assertEquals(listOf("NO DATA"), mock.sendCommand("0160"))
    }

    @Test
    fun liveMode1ResponsesUseValidHexAndExpectedServicePid() = runBlocking {
        val mock = MockComm()
        val commands = listOf(
            "0101", "0102", "0103", "0104", "0105", "0106", "0107", "0108",
            "0109", "010A", "010B", "010C", "010D", "010E", "010F", "0110",
            "0111", "0112", "0113", "0114", "0115", "0116", "0117", "0118",
            "0119", "011A", "011B", "011C", "011D", "011E", "011F", "0121",
            "0122", "0123", "0124", "0125", "0126", "0127", "0128", "0129",
            "012A", "012B", "012C", "012D", "012E", "012F", "0130", "0131",
            "0132", "0133", "0134", "0135", "0136", "0137", "0138", "0139",
            "013A", "013B", "013C", "013D", "013E", "013F", "0141", "0142",
            "0143", "0144", "0145", "0146", "0147", "0148", "0149", "014A",
            "014B", "014C", "014D", "014E", "014F", "0150", "0151", "0152",
            "0153", "0154", "0155", "0156", "0157", "0158", "0159", "015A",
            "015B", "015C", "015D", "015E", "015F",
        )

        for (command in commands) {
            val response = mock.sendCommand(command).single()
            assertTrue(response.startsWith("7E8"), "Expected header for $command, got $response")
            assertTrue(response.contains("41 ${command.takeLast(2)}"), "Expected service/PID for $command, got $response")
            val bytes = response.split(" ").drop(1)
            assertTrue(bytes.all { it.matches(Regex("[0-9A-F]{2}")) }, "Invalid hex in $command: $response")
        }
    }

    @Test
    fun timeDependentMode1ResponsesCoverWarmReadinessAndFuelStates() = runBlocking {
        val mock = MockComm()

        mock.setElapsedSeconds(119.0)
        val readiness = mock.sendCommand("0101").single()
        val thisCycleReadiness = mock.sendCommand("0141").single()
        assertTrue(readiness.contains("41 01 87 00 EF 02"), readiness)
        assertTrue(thisCycleReadiness.contains("41 41 87 00 EF 02"), thisCycleReadiness)

        mock.setElapsedSeconds(70.0)
        val warmFuelStatus = mock.sendCommand("0103").payloadBytes().takeLast(2)
        assertEquals(listOf(0x02, 0x02), warmFuelStatus)

        mock.setElapsedSeconds(60.0)
        val coastingFuelStatus = mock.sendCommand("0103").payloadBytes().takeLast(2)
        assertEquals(listOf(0x02, 0x02), coastingFuelStatus)
    }

    @Test
    fun timeDependentSpeedAndRpmCoverOscillationBranches() = runBlocking {
        val mock = MockComm()

        mock.setElapsedSeconds(20.0)
        assertTrue(mock.sendCommand("010D").single().contains("41 0D"))
        assertTrue(mock.sendCommand("010C").single().contains("41 0C"))

        mock.setElapsedSeconds(45.0)
        assertTrue(mock.sendCommand("010D").single().contains("41 0D"))
        assertTrue(mock.sendCommand("010C").single().contains("41 0C"))
    }
}
