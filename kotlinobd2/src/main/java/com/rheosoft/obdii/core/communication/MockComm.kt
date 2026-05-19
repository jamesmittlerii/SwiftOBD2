package com.rheosoft.obdii.core.communication

import com.rheosoft.obdii.core.AdapterConnectionState
import com.rheosoft.obdii.core.OBDServiceDelegate
import com.rheosoft.obdii.core.PeripheralInfo
import com.rheosoft.obdii.core.protocols.CommProtocol
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

private const val NO_DATA = "NO DATA"

class MockComm : CommProtocol {
    private val stateFlow = MutableStateFlow(AdapterConnectionState.disconnected)
    override val connectionState: StateFlow<AdapterConnectionState> = stateFlow
    override var obdDelegate: OBDServiceDelegate? = null

    private var echoEnabled = false
    private var headersEnabled = true
    private val startAt = System.currentTimeMillis()
    private val mode1PidHandlers: Map<String, (Double, String) -> String> = buildMap {
        put("00") { _, _ -> "41 00 FF FF FF FF" }
        put("20") { _, _ -> "41 20 FF FF FF FF" }
        put("40") { _, _ -> "41 40 FF FF FF FE" }
        put("0C") { elapsed, _ ->
            val rpm = currentMockRpm(currentMockSpeed(elapsed)).toInt().coerceIn(800, 8000)
            val raw = rpm * 4
            "41 0C %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("05") { elapsed, _ ->
            val temp = ((elapsed.coerceIn(0.0, 60.0) / 60.0) * 100.0).toInt()
            "41 05 %02X".format((temp + 40).coerceIn(0, 255))
        }
        put("42") { elapsed, _ ->
            val volts = (13.6 + smoothNoise(elapsed, seed = 1.0, scale = 0.15)).coerceIn(12.2, 14.6)
            val raw = (volts * 1000).toInt().coerceIn(0, 65535)
            "41 42 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("01") { elapsed, _ -> composeMode1Status(elapsed) }
        put("03") { elapsed, _ -> composeMode1FuelStatus(elapsed) }
        put("02") { _, _ -> "41 02 03 01" }
        put("04") { elapsed, _ -> "41 04 ${hexByte((0.1 + 0.8 * normalizedRpm(elapsed)) * 255.0)}" }
        put("06") { elapsed, _ -> "41 06 ${fuelTrimByte(elapsed, 0.05)}" }
        put("07") { elapsed, _ -> "41 07 ${fuelTrimByte(elapsed, 0.02)}" }
        put("08") { elapsed, _ -> "41 08 ${fuelTrimByte(elapsed + 0.7, 0.05)}" }
        put("09") { elapsed, _ -> "41 09 ${fuelTrimByte(elapsed + 0.7, 0.02)}" }
        put("0A") { _, _ -> "41 0A ${hexByte((400.0 / 3.0).coerceIn(0.0, 255.0))}" }
        put("0B") { elapsed, _ ->
            "41 0B ${hexByte((25.0 + (normalizedRpm(elapsed) * 70.0)).coerceIn(20.0, 100.0))}"
        }
        put("0F") { elapsed, _ ->
            val intake = ((elapsed.coerceIn(0.0, 60.0) / 60.0) * 70.0).toInt()
            "41 0F %02X".format((intake + 40).coerceIn(0, 255))
        }
        put("0D") { elapsed, _ ->
            val speed = currentMockSpeed(elapsed).toInt().coerceIn(0, 120)
            "41 0D %02X".format(speed)
        }
        put("0E") { elapsed, _ ->
            val adv = (10.0 + normalizedRpm(elapsed) * 25.0).coerceIn(2.0, 45.0)
            "41 0E ${hexByte((adv + 64.0) * 2.0)}"
        }
        put("10") { elapsed, _ ->
            val maf = (2.0 + normalizedRpm(elapsed) * 118.0).coerceIn(2.0, 200.0)
            val raw = (maf * 100.0).toInt().coerceIn(0, 65535)
            "41 10 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("11") { elapsed, _ ->
            val demand = throttleDemandPercent(elapsed) / 100.0
            "41 11 ${hexByte(demand * 255.0)}"
        }
        put("12") { _, _ -> "41 12 04" }
        put("13") { _, _ -> "41 13 03" }
        listOf("14", "15", "18", "19").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid -> "41 $pid ${o2NarrowbandBytes(elapsed, pid)}" }
        }
        listOf("16", "17", "1A", "1B").forEach { requestedPid ->
            put(requestedPid) { _, pid -> "41 $pid 80 80" }
        }
        put("1C") { _, _ -> "41 1C 03" }
        put("1D") { _, _ -> "41 1D 00" }
        put("1E") { _, _ -> "41 1E 00" }
        put("1F") { elapsed, _ ->
            val runtime = elapsed.toInt().coerceIn(0, 65535)
            "41 1F %02X %02X".format((runtime shr 8) and 0xFF, runtime and 0xFF)
        }
        listOf("21", "31").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val km = (currentMockSpeed(elapsed) * (elapsed / 3600.0)).toInt().coerceIn(0, 65535)
                "41 $pid %02X %02X".format((km shr 8) and 0xFF, km and 0xFF)
            }
        }
        put("22") { elapsed, _ ->
            val kpa =
                (300.0 + normalizedRpm(elapsed) * 100.0 + smoothNoise(elapsed, 22.0, 10.0))
                    .coerceIn(200.0, 600.0)
            val raw = (kpa / 10.0).toInt().coerceIn(0, 65535)
            "41 22 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("23") { _, _ -> "41 23 02 BF" }
        listOf("24", "25", "26", "27", "28", "29", "2A", "2B").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val mv =
                    (2500.0 + smoothNoise(elapsed, 23.0 + pid.hexSeed(), 200.0) * 1000.0)
                        .coerceIn(0.0, 8192.0)
                val raw = mv.toInt().coerceIn(0, 8192)
                "41 $pid %02X %02X 80 00".format((raw shr 8) and 0xFF, raw and 0xFF)
            }
        }
        put("2C") { elapsed, _ -> "41 2C ${hexByte((0.2 + 0.2 * sin(elapsed * 0.3)) * 255.0)}" }
        put("2D") { elapsed, _ -> "41 2D ${hexByte(128 + smoothNoise(elapsed, 24.0, 0.05) * 255.0)}" }
        put("2E") { elapsed, _ -> "41 2E ${hexByte((0.1 + 0.3 * sin(elapsed * 0.2)) * 255.0)}" }
        put("2F") { elapsed, _ ->
            val fuel = (90.0 - (elapsed / 10.0)).coerceIn(0.0, 100.0)
            "41 2F ${hexByte((fuel / 100.0) * 255.0)}"
        }
        put("30") { elapsed, _ ->
            val cycles = (elapsed / 300.0).toInt().coerceIn(0, 40)
            "41 30 00 00 %02X".format(cycles)
        }
        put("32") { elapsed, _ ->
            val pa = (100 + smoothNoise(elapsed, 25.0, 50.0) * 100.0).toInt().coerceIn(-32768, 32767)
            val raw = pa and 0xFFFF
            "41 32 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("33") { elapsed, _ ->
            val kpa = (101.0 + smoothNoise(elapsed, 9.0, 0.6)).coerceIn(95.0, 105.0)
            "41 33 ${hexByte(kpa)}"
        }
        listOf("34", "35", "36", "37", "38", "39", "3A", "3B").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid -> "41 $pid ${hexByte(128 + sin(elapsed * 1.5) * 20.0)} 00" }
        }
        listOf("3C", "3D", "3E", "3F").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val tC =
                    300.0 + 250.0 * (0.5 + 0.5 * sin(elapsed * 0.1)) +
                        smoothNoise(elapsed, 27.0 + pid.hexSeed(), 15.0)
                val raw = ((tC + 40.0) * 10.0).toInt().coerceIn(0, 65535)
                "41 $pid %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
            }
        }
        put("41") { elapsed, _ -> composeMode1Status(elapsed).replace("41 01", "41 41") }
        put("43") { elapsed, _ ->
            val load = (0.1 + 0.8 * normalizedRpm(elapsed) + smoothNoise(elapsed, 28.0, 0.05)).coerceIn(0.0, 1.0)
            val raw = (load * 65535.0).toInt().coerceIn(0, 65535)
            "41 43 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("44") { elapsed, _ ->
            val lambda = (1.0 + smoothNoise(elapsed, 29.0, 0.03)).coerceIn(0.9, 1.1)
            val raw = (lambda * 32768.0).toInt().coerceIn(0, 65535)
            "41 44 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        listOf("45", "47", "48", "49", "4A", "4B", "4C", "5A").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val pct =
                    (0.2 + 0.4 * (0.5 + 0.5 * sin(elapsed * 0.3)) +
                        smoothNoise(elapsed, 30.0 + pid.hexSeed(), 0.03))
                        .coerceIn(0.0, 1.0)
                "41 $pid ${hexByte(pct * 255.0)}"
            }
        }
        put("46") { _, _ -> "41 46 32" }
        put("4D") { _, _ -> "41 4D 00 00" }
        put("4E") { elapsed, _ ->
            val seconds = elapsed.toInt().coerceIn(0, 65535)
            "41 4E %02X %02X".format((seconds shr 8) and 0xFF, seconds and 0xFF)
        }
        put("4F") { _, _ -> "41 4F FF FF FF FF FF" }
        put("50") { _, _ ->
            val maxMaf = 300.0
            val raw = (maxMaf * 50.0).toInt().coerceIn(0, 65535)
            "41 50 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("51") { _, _ -> "41 51 01" }
        put("52") { _, _ -> "41 52 1A" }
        listOf("53", "54").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val pa = (if (pid == "53") 300 else 250) + smoothNoise(elapsed, 31.0 + pid.hexSeed(), 60.0) * 100.0
                val raw = pa.toInt().coerceIn(-32768, 32767) and 0xFFFF
                "41 $pid %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
            }
        }
        listOf("55", "56", "57", "58").forEach { requestedPid ->
            put(requestedPid) { elapsed, pid ->
                val scale = if (pid == "56" || pid == "58") 0.03 else 0.06
                "41 $pid ${hexByte(128 + smoothNoise(elapsed, 33.0 + pid.hexSeed(), scale) * 255.0)} 00"
            }
        }
        put("59") { elapsed, _ ->
            val kpa = (400.0 + smoothNoise(elapsed, 37.0, 40.0)).coerceIn(360.0, 440.0)
            val raw = (kpa / 10.0).toInt().coerceIn(0, 65535)
            "41 59 %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("5B") { elapsed, _ ->
            val percent = (90.0 - (elapsed / 600.0)).coerceIn(50.0, 90.0)
            val raw = ((percent / 100.0) * 65535.0).toInt().coerceIn(0, 65535)
            "41 5B %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("5C") { elapsed, _ ->
            val temp = 20.0 + (100.0 - 20.0) * (1.0 - exp(-elapsed / 900.0)) + smoothNoise(elapsed, 11.0, 1.5)
            "41 5C ${hexByte((temp + 40.0).coerceIn(0.0, 255.0))}"
        }
        put("5D") { elapsed, _ ->
            val rpmN = normalizedRpm(elapsed)
            val deg = (5.0 + 15.0 * (1.0 - rpmN) - 2.5 * rpmN + smoothNoise(elapsed, 12.0, 0.8)).coerceIn(-5.0, 25.0)
            val raw = (deg * 10.0 + 21000.0).toInt().coerceIn(0, 65535)
            "41 5D %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("5E") { elapsed, _ ->
            val rpmN = normalizedRpm(elapsed)
            val lph = (1.2 + 18.0 * rpmN + 10.0 * rpmN + smoothNoise(elapsed, 13.0, 0.8)).coerceIn(0.5, 60.0)
            val raw = (lph * 20.0).toInt().coerceIn(0, 65535)
            "41 5E %02X %02X".format((raw shr 8) and 0xFF, raw and 0xFF)
        }
        put("5F") { _, _ -> "41 5F 01" }
    }

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
        if (trimmed == "03") return withEcho(trimmed, composeMode3TroubleCodes())
        if (trimmed.startsWith("01")) return withEcho(trimmed, composeMode1(trimmed))
        if (trimmed.startsWith("06")) return withEcho(trimmed, composeMode6(trimmed))
        if (trimmed.startsWith("09")) return withEcho(trimmed, composeMode9(trimmed))
        if (trimmed.startsWith("22")) return withEcho(trimmed, composeMode22(trimmed))
        return withEcho(trimmed, listOf(NO_DATA))
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

    private fun composeMode1(command: String): List<String> {
        val pid = command.takeLast(2)
        val elapsed = sessionElapsed()
        val payload = mode1PidHandlers[pid]?.invoke(elapsed, pid) ?: NO_DATA
        if (payload == NO_DATA) return listOf(payload)
        return listOf(frame(payload))
    }

    private fun composeMode3TroubleCodes(): List<String> {
        // Keep this multi-frame to match Swift behavior.
        return listOf(
            frame("10 10 43 07 03 00 01 70"),
            frame("21 01 01 01 04 02 07 04"),
            frame("22 11 04 20 00 00 00 00"),
        )
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

    private fun composeMode6(command: String): List<String> {
        val pid = command.takeLast(2)
        val payload = when (pid) {
            "00" -> "46 00 C0 00 00 01 00"
            "20" -> "46 20 C0 00 00 01 00"
            "40" -> "46 40 C0 00 00 01 00"
            "60" -> "46 60 C0 00 00 01 00"
            "80" -> "46 80 C0 00 00 01 00"
            "A0" -> "46 A0 C0 00 00 01 00"
            else -> NO_DATA
        }
        return if (payload == NO_DATA) listOf(payload) else listOf(frame(payload))
    }

    private fun composeMode9(command: String): List<String> {
        return when (command) {
            "0900" -> listOf(frame("49 00 55 40 57 F0"))
            "0902" -> listOf(
                frame("10 14 49 02 01 31 4E 34"),
                frame("21 41 4C 33 41 50 37 44"),
                frame("22 43 31 39 39 35 38 33"),
            )
            else -> listOf(NO_DATA)
        }
    }

    private fun composeMode22(command: String): List<String> {
        val payload = when (command) {
            "221144" -> "62 11 44 32 00"
            "221470" -> "62 14 70 31 00"
            "221940" -> "62 19 40 49 00"
            "221154" -> "62 11 54 64 00"
            else -> NO_DATA
        }
        return if (payload == NO_DATA) listOf(payload) else listOf(frame(payload))
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
            val phase = 2.0 * PI * (((elapsed - rampDuration) % oscillationPeriod) / oscillationPeriod)
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

    private fun normalizedRpm(elapsed: Double): Double {
        val rpm = currentMockRpm(currentMockSpeed(elapsed))
        return ((rpm - 800.0) / (8000.0 - 800.0)).coerceIn(0.0, 1.0)
    }

    private fun throttleDemandPercent(elapsed: Double): Double {
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
        return (demand * 100.0).coerceIn(0.0, 100.0)
    }

    private fun fuelTrimByte(elapsed: Double, amplitude: Double): String {
        val centered = 128 + ((sin(elapsed * 0.2) * amplitude) * 255.0)
        return hexByte(centered)
    }

    private fun o2NarrowbandBytes(elapsed: Double, pid: String): String {
        val seed = pid.hexSeed()
        val v = (0.5 + sin((elapsed + seed) * 0.4) * 0.25).coerceIn(0.1, 0.9)
        val a = ((v / 1.275) * 255.0).toInt().coerceIn(0, 255)
        return "${hexByte(a)} 80"
    }

    private fun frame(body: String): String {
        val tokens = body.split(" ").filter { it.isNotBlank() }
        val firstByte = tokens.firstOrNull()?.toIntOrNull(16) ?: 0
        // If it's already a PCI byte (Single/First/Consecutive/FlowControl), don't add another.
        // PCI bytes are 0x00..0x3F for Single/First/Consecutive/FlowControl
        val hasPci = firstByte <= 0x3F

        val dataTokens =
            if (hasPci) {
                tokens
            } else {
                val pci = "%02X".format(tokens.size)
                listOf(pci) + tokens
            }
        // Swift mock pads short ISO-TP payloads to a full 8-byte CAN frame (00 fill).
        val padded = buildList {
            addAll(dataTokens)
            while (size < 8) add("00")
        }
        val content = padded.joinToString(" ")

        return if (headersEnabled) "7E8 $content" else content
    }

    private fun withEcho(command: String, responses: List<String>): List<String> {
        if (!echoEnabled) return responses
        return listOf(command) + responses
    }

    private fun hexByte(value: Number): String = value.toDouble().toInt().coerceIn(0, 255).let { "%02X".format(it) }

    private fun String.hexSeed(): Double = toIntOrNull(16)?.toDouble() ?: 0.0

    override fun disconnectPeripheral() {
        stateFlow.value = AdapterConnectionState.disconnected
        obdDelegate?.connectionStateChanged(AdapterConnectionState.disconnected)
    }

    override suspend fun scanForPeripherals(): List<PeripheralInfo> = emptyList()
}
