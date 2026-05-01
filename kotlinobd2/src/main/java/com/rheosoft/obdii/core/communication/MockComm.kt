package com.rheosoft.obdii.core.communication

import com.rheosoft.obdii.core.AdapterConnectionState
import com.rheosoft.obdii.core.OBDServiceDelegate
import com.rheosoft.obdii.core.PeripheralInfo
import com.rheosoft.obdii.core.protocols.CommProtocol
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class MockComm : CommProtocol {
    private val stateFlow = MutableStateFlow(AdapterConnectionState.disconnected)
    override val connectionState: StateFlow<AdapterConnectionState> = stateFlow
    override var obdDelegate: OBDServiceDelegate? = null

    private var echoEnabled = false
    private var headersEnabled = true
    private val startAt = System.currentTimeMillis()

    override suspend fun connectAsync(timeoutMs: Long, peripheral: PeripheralInfo?) {
        stateFlow.value = AdapterConnectionState.connecting
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connecting)
        delay(80)
        stateFlow.value = AdapterConnectionState.connectedToAdapter
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connectedToAdapter)
    }

    override suspend fun sendCommand(command: String, retries: Int): List<String> {
        val trimmed = command.trim().uppercase()
        if (trimmed.startsWith("AT")) return handleAt(trimmed)
        if (trimmed == "03") return listOf(composeMode3TroubleCodes())
        if (trimmed.startsWith("01")) return listOf(composeMode1(trimmed))
        return listOf("NO DATA")
    }

    private fun handleAt(command: String): List<String> {
        val response = when (command) {
            "ATZ" -> "ELM327 v1.5"
            "ATE0" -> { echoEnabled = false; "OK" }
            "ATE1" -> { echoEnabled = true; "OK" }
            "ATH0" -> { headersEnabled = false; "OK" }
            "ATH1" -> { headersEnabled = true; "OK" }
            "ATL0", "ATS0", "ATSP0", "ATAT1", "ATAL" -> "OK"
            else -> "OK"
        }
        return if (echoEnabled) listOf(command, response) else listOf(response)
    }

    private fun composeMode1(command: String): String {
        val pid = command.takeLast(2)
        val elapsed = sessionElapsed()
        val payload = when (pid) {
            "0C" -> {
                val rpm = currentMockRpm(currentMockSpeed(elapsed)).toInt().coerceIn(800, 8000)
                val raw = rpm * 4
                "41 0C %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
            }
            "05" -> {
                val temp = ((elapsed.coerceIn(0.0, 60.0) / 60.0) * 100.0).toInt()
                "41 05 %02X".format((temp + 40).coerceIn(0, 255))
            }
            "42" -> {
                val volts = (13.6 + smoothNoise(elapsed, seed = 1.0, scale = 0.15)).coerceIn(12.2, 14.6)
                val raw = (volts * 1000).toInt().coerceIn(0, 65535)
                "41 42 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
            }
            "01" -> {
                composeMode1Status(elapsed)
            }
            "03" -> {
                composeMode1FuelStatus(elapsed)
            }
            "0F" -> {
                val intake = ((elapsed.coerceIn(0.0, 60.0) / 60.0) * 70.0).toInt()
                "41 0F %02X".format((intake + 40).coerceIn(0, 255))
            }
            "0D" -> {
                val speed = currentMockSpeed(elapsed).toInt().coerceIn(0, 120)
                "41 0D %02X".format(speed)
            }
            else -> "NO DATA"
        }
        if (payload == "NO DATA") return payload
        return if (headersEnabled) "7E8 $payload" else payload
    }

    private fun composeMode3TroubleCodes(): String {
        val sampleCodes = listOf("P0300", "P0170", "P0101", "P0104", "P0207", "P0411", "P0420")
        fun encodeDtc(code: String): Pair<Int, Int> {
            val letterBits = when (code.firstOrNull()) {
                'P' -> 0
                'C' -> 1
                'B' -> 2
                'U' -> 3
                else -> 0
            }
            val d1 = code.getOrNull(1)?.digitToIntOrNull(16) ?: 0
            val d2 = code.getOrNull(2)?.digitToIntOrNull(16) ?: 0
            val d3 = code.getOrNull(3)?.digitToIntOrNull(16) ?: 0
            val d4 = code.getOrNull(4)?.digitToIntOrNull(16) ?: 0
            val a = (letterBits shl 6) or (d1 shl 4) or d2
            val b = (d3 shl 4) or d4
            return a to b
        }
        val payload = mutableListOf<Int>()
        payload += 0x43
        payload += sampleCodes.size
        sampleCodes.forEach { code ->
            val (a, b) = encodeDtc(code)
            payload += a
            payload += b
        }
        val hex = payload.joinToString(" ") { "%02X".format(it) }
        return if (headersEnabled) "7E8 $hex" else hex
    }

    private fun composeMode1Status(elapsed: Double): String {
        val t = min(max(elapsed, 0.0), 120.0)
        val stages = (t / 12.0).toInt()

        // Mirror Swift mock defaults: MIL ON + 7 DTCs
        val a0 = 0x87

        // Byte A: comprehensive/fuel/misfire not-ready flags (1 = not ready)
        var a = 0x70

        // Byte B: supported monitors (gasoline path)
        val b = 0xEF

        // Byte C: readiness for supported monitors (1 = not ready)
        var c = 0xEF

        if (stages >= 1) a = a and 0xBF // comprehensive ready
        if (stages >= 2) a = a and 0xDF // fuel ready
        if (stages >= 3) a = a and 0xEF // misfire ready
        if (stages >= 4) c = c and 0xBF // O2 heater ready
        if (stages >= 5) c = c and 0xDF // O2 sensor ready
        if (stages >= 6) c = c and 0xFE // catalyst ready
        if (stages >= 7) c = c and 0xFB // evap ready
        if (stages >= 8) c = c and 0x7F // EGR/VVT ready
        if (stages >= 9) c = c and 0xF7 // secondary air ready
        if (stages >= 10) c = c and 0xFD // heated catalyst ready

        return "41 01 %02X %02X %02X %02X".format(a0, a, b, c)
    }

    private fun composeMode1FuelStatus(elapsed: Double): String {
        // Mirror Swift mock logic:
        // 1 = open loop (cold), 2 = closed loop, 3 = open loop (load/fuel cut).
        val tempC = ((elapsed.coerceIn(0.0, 60.0) / 60.0) * 100.0)
        val speed = currentMockSpeed(elapsed)
        val rpm = currentMockRpm(speed)
        val rpmN = ((rpm - 800.0) / (8000.0 - 800.0)).coerceIn(0.0, 1.0)

        var demand = 0.15 + 0.45 * rpmN * rpmN
        demand += smoothNoise(elapsed, seed = 5.5, scale = 0.015)

        val sampleDt = 0.2
        val prevSpeed = currentMockSpeed((elapsed - sampleDt).coerceAtLeast(0.0))
        val accel = (speed - prevSpeed) / sampleDt
        val isIdle = rpm < 1100.0 && speed < 3.0
        if (isIdle) demand = max(demand, 0.06)
        val isCoasting = rpm > 1200.0 && accel < -4.0 && !isIdle
        if (isCoasting) demand = min(demand, 0.03 + 0.03 * rpmN)
        val throttlePct = demand * 100.0

        val statusCode = when {
            tempC < 60.0 -> 0x01
            throttlePct < 3.0 -> 0x03
            else -> 0x02
        }
        return "41 03 %02X %02X".format(statusCode, statusCode)
    }

    private fun sessionElapsed(): Double {
        val elapsed = (System.currentTimeMillis() - startAt) / 1000.0
        return elapsed % 120.0
    }

    private fun smoothNoise(elapsed: Double, seed: Double, scale: Double): Double {
        val n = sin((elapsed + seed) * 0.2) * 0.6 + sin((elapsed * 0.07) + seed * 3.1) * 0.4
        return n * scale
    }

    private fun currentMockSpeed(elapsed: Double): Double {
        val rampDuration = 15.0
        val minSpeed = 20.0
        val maxSpeed = 70.0
        val midpoint = (minSpeed + maxSpeed) / 2.0
        val amplitude = (maxSpeed - minSpeed) / 2.0
        return if (elapsed < rampDuration) {
            ((elapsed / rampDuration) * minSpeed).coerceIn(0.0, minSpeed)
        } else {
            val oscillationPeriod = 30.0
            val phase = 2.0 * Math.PI * (((elapsed - rampDuration) % oscillationPeriod) / oscillationPeriod)
            midpoint + amplitude * sin(phase)
        }
    }

    private fun currentMockRpm(speedValue: Double): Double {
        return when {
            speedValue <= 0.5 -> 800.0
            speedValue < 20.0 -> 800.0 + 360.0 * speedValue
            speedValue < 50.0 -> 1500.0 + (6500.0 / 30.0) * (speedValue - 20.0)
            else -> 1800.0 + 310.0 * (speedValue - 50.0)
        }
    }

    override fun disconnectPeripheral() {
        stateFlow.value = AdapterConnectionState.disconnected
        obdDelegate?.connectionStateChanged(AdapterConnectionState.disconnected)
    }

    override suspend fun scanForPeripherals(): List<PeripheralInfo> = emptyList()
}
