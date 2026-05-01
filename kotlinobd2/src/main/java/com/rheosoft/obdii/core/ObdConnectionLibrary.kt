package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.ble.BlePlatformAdapter
import com.rheosoft.obdii.core.communication.ble.UnsupportedBleAdapter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class OBDConnectionState { disconnected, connecting, connected, failed }
data class MeasurementResult(val value: Double, val unit: String)
data class TroubleCodeMetadata(
    val code: String,
    val title: String = "",
    val description: String = "",
    val severity: String = "",
    val causes: List<String> = emptyList(),
    val remedies: List<String> = emptyList(),
)
data class StatusCodeMetadata(val code: String, val description: String)
data class ReadinessMonitor(val name: String, val supported: Boolean, val ready: Boolean)
data class Status(val milOn: Boolean, val dtcCount: Int, val monitors: List<ReadinessMonitor> = emptyList())

data class PIDStats(
    val pid: String,
    val latest: MeasurementResult,
    val min: Double = latest.value,
    val max: Double = latest.value,
    val sampleCount: Int = 1,
) {
    fun copyWith(measurement: MeasurementResult): PIDStats = copy(
        latest = measurement,
        min = kotlin.math.min(min, measurement.value),
        max = kotlin.math.max(max, measurement.value),
        sampleCount = sampleCount + 1,
    )
}

interface PidStatsProviding {
    val pidStats: Map<String, PIDStats>
    fun statsFor(pidCommand: String): PIDStats?
    val pidStatsStream: StateFlow<Map<String, PIDStats>>
}

interface DiagnosticsProviding {
    val troubleCodes: List<TroubleCodeMetadata>?
    val diagnosticsStream: StateFlow<List<TroubleCodeMetadata>?>
}

interface FuelStatusProviding {
    val fuelStatus: List<StatusCodeMetadata?>?
    val fuelStatusStream: StateFlow<List<StatusCodeMetadata?>?>
}

interface MilStatusProviding {
    val milStatus: Status?
    val milStatusStream: StateFlow<Status?>
}

interface OBDConnectionControlling {
    val connectionState: OBDConnectionState
    fun updateConnectionDetails()
    suspend fun connect()
    fun disconnect()
    val connectionStateStream: StateFlow<OBDConnectionState>
}

object ObdConnectionLibrary : PidStatsProviding, DiagnosticsProviding, FuelStatusProviding, MilStatusProviding, OBDConnectionControlling {
    override var connectionState: OBDConnectionState = OBDConnectionState.disconnected
        private set
    override var troubleCodes: List<TroubleCodeMetadata>? = null
        private set
    override var fuelStatus: List<StatusCodeMetadata?>? = null
        private set
    override var milStatus: Status? = null
        private set
    var connectedPeripheralName: String? = null
        private set
    override var pidStats: Map<String, PIDStats> = emptyMap()
        private set

    private val connFlow = MutableStateFlow(connectionState)
    private val statsFlow = MutableStateFlow(pidStats)
    private val diagnosticsFlow = MutableStateFlow<List<TroubleCodeMetadata>?>(null)
    private val fuelFlow = MutableStateFlow<List<StatusCodeMetadata?>?>(null)
    private val milFlow = MutableStateFlow<Status?>(null)
    private val ioScope = CoroutineScope(Dispatchers.Default + Job())
    private var pollJob: Job? = null
    private var serviceMirrorJob: Job? = null
    private var service = ObdService(LibraryConnectionType.demo)
    private var bleAdapter: BlePlatformAdapter = UnsupportedBleAdapter()
    private var connectionType = LibraryConnectionType.demo
    private var wifiHost = "192.168.0.10"
    private var wifiPort = 35000
    private var interestedPids: Set<String> = emptySet()
    private var lastStreamingPids: Set<String> = emptySet()
    private val defaultPids = setOf("010C", "0105", "0142", "010F", "010D", "0101", "0103")
    override val connectionStateStream: StateFlow<OBDConnectionState> = connFlow.asStateFlow()
    override val pidStatsStream: StateFlow<Map<String, PIDStats>> = statsFlow.asStateFlow()
    override val diagnosticsStream: StateFlow<List<TroubleCodeMetadata>?> = diagnosticsFlow.asStateFlow()
    override val fuelStatusStream: StateFlow<List<StatusCodeMetadata?>?> = fuelFlow.asStateFlow()
    override val milStatusStream: StateFlow<Status?> = milFlow.asStateFlow()

    fun initialize() {
        service = ObdService(connectionType, wifiHost, wifiPort, bleAdapter)
        bindServiceMirrors()
    }

    fun configureTransport(type: LibraryConnectionType, host: String? = null, port: Int? = null) {
        connectionType = type
        if (host != null) wifiHost = host
        if (port != null) wifiPort = port
        service.switchConnectionType(type, host, port)
        bindServiceMirrors()
    }

    fun setBleAdapter(adapter: BlePlatformAdapter) {
        bleAdapter = adapter
        service.setBleAdapter(adapter)
    }

    fun setInterestedPids(interested: Set<String>) {
        val normalized = interested.map { it.trim().uppercase() }.filter { it.isNotBlank() }.toSet()
        if (normalized == interestedPids) return
        interestedPids = normalized
        if (connectionState == OBDConnectionState.connected) {
            restartPolling()
        } else {
            lastStreamingPids = emptySet()
        }
    }

    fun onUnitsChanged() {
        resetAllStats()
        if (connectionState == OBDConnectionState.connected) {
            restartPolling()
        }
    }

    override suspend fun connect() {
        if (connectionState == OBDConnectionState.connected || connectionState == OBDConnectionState.connecting) return
        connectionState = OBDConnectionState.connecting
        connFlow.value = connectionState
        try {
            service.startConnection(timeoutMs = 20_000)
            connectionState = OBDConnectionState.connected
            connFlow.value = connectionState
            connectedPeripheralName = service.connectedPeripheral?.name
            startPolling()
        } catch (t: Throwable) {
            connectionState = OBDConnectionState.failed
            connFlow.value = connectionState
            throw t
        }
    }

    override fun disconnect() {
        pollJob?.cancel()
        pollJob = null
        service.stopConnection()
        clearForTerminalState()
        connectionState = OBDConnectionState.disconnected
        connFlow.value = connectionState
    }

    override fun updateConnectionDetails() {
        if (connectionState != OBDConnectionState.disconnected) {
            disconnect()
        }
        lastStreamingPids = emptySet()
    }

    override fun statsFor(pidCommand: String): PIDStats? = pidStats[pidCommand]

    fun resetForTests() {
        disconnect()
        connectionState = OBDConnectionState.disconnected
        connFlow.value = connectionState
        interestedPids = emptySet()
        lastStreamingPids = emptySet()
    }

    private fun bindServiceMirrors() {
        serviceMirrorJob?.cancel()
        serviceMirrorJob = ioScope.launch {
            service.connectionState.collectLatest { handleServiceConnectionState(it) }
        }
    }

    private fun handleServiceConnectionState(state: AdapterConnectionState) {
        when (state) {
            AdapterConnectionState.disconnected -> {
                clearForTerminalState()
                connectionState = OBDConnectionState.disconnected
                connFlow.value = connectionState
            }
            AdapterConnectionState.error -> {
                clearForTerminalState()
                connectionState = OBDConnectionState.failed
                connFlow.value = connectionState
            }
            AdapterConnectionState.connecting -> {
                if (connectionState != OBDConnectionState.connecting) {
                    connectionState = OBDConnectionState.connecting
                    connFlow.value = connectionState
                }
            }
            AdapterConnectionState.connectedToAdapter,
            AdapterConnectionState.connectedToVehicle,
            -> {
                if (connectionState != OBDConnectionState.connected) {
                    connectionState = OBDConnectionState.connected
                    connFlow.value = connectionState
                }
            }
        }
        connectedPeripheralName = service.connectedPeripheral?.name
    }

    private fun clearForTerminalState() {
        pollJob?.cancel()
        pollJob = null
        lastStreamingPids = emptySet()
        pidStats = emptyMap()
        statsFlow.value = pidStats
        troubleCodes = null
        fuelStatus = null
        milStatus = null
        diagnosticsFlow.value = null
        fuelFlow.value = null
        milFlow.value = null
        connectedPeripheralName = null
    }

    private fun startPolling() {
        pollJob?.cancel()
        val streamPids = if (interestedPids.isEmpty()) defaultPids else interestedPids
        if (streamPids.isEmpty()) {
            lastStreamingPids = emptySet()
            return
        }
        if (streamPids == lastStreamingPids) return
        lastStreamingPids = streamPids
        val seeds = mutableMapOf<String, PIDStats>()
        pollJob = ioScope.launch {
            while (isActive && connectionState == OBDConnectionState.connected) {
                for (pid in streamPids) {
                    val lines = runCatching { service.sendCommand(pid) }.getOrDefault(emptyList())
                    handlePidResponse(pid, lines, seeds)
                }
                pidStats = seeds.toMap()
                statsFlow.value = pidStats
                delay(300)
            }
        }
    }

    private fun restartPolling() {
        pollJob?.cancel()
        pollJob = null
        startPolling()
    }

    private fun resetAllStats() {
        pidStats = pidStats.mapValues { (_, existing) ->
            existing.copy(
                min = existing.latest.value,
                max = existing.latest.value,
                sampleCount = 1,
            )
        }
        statsFlow.value = pidStats
    }

    private fun handlePidResponse(
        pid: String,
        lines: List<String>,
        statsAccumulator: MutableMap<String, PIDStats>,
    ) {
        val hex = parseHexBytes(lines)
        if (hex.isEmpty()) return

        when (pid.uppercase()) {
            "0103" -> {
                fuelStatus = parseFuelStatus(hex)
                fuelFlow.value = fuelStatus
            }
            "0101" -> {
                milStatus = parseMilStatus(hex)
                milFlow.value = milStatus
            }
            "03" -> {
                troubleCodes = parseTroubleCodes(hex)
                diagnosticsFlow.value = troubleCodes
            }
            else -> {
                val measurement = parsePidMeasurement(pid, hex) ?: return
                val existing = statsAccumulator[pid]
                statsAccumulator[pid] = existing?.copyWith(measurement) ?: PIDStats(pid, measurement)
            }
        }
    }

    private fun parseFuelStatus(hex: List<Int>): List<StatusCodeMetadata?>? {
        val modeIdx = hex.indexOfFirst { it == 0x41 }
        val start = if (modeIdx >= 0) modeIdx else 0
        if (start + 3 >= hex.size) return null
        val a = hex[start + 2]
        val b = hex[start + 3]
        fun decodeByte(v: Int): StatusCodeMetadata? = when {
            v and 0x01 != 0 -> StatusCodeMetadata("1", "Open loop due to insufficient engine temperature")
            v and 0x02 != 0 -> StatusCodeMetadata("2", "Closed loop, using oxygen sensor feedback")
            v and 0x04 != 0 -> StatusCodeMetadata("4", "Open loop due to engine load or fuel cut")
            v and 0x08 != 0 -> StatusCodeMetadata("8", "Open loop due to system failure")
            v and 0x10 != 0 -> StatusCodeMetadata("16", "Closed loop using at least one oxygen sensor")
            else -> null
        }
        return listOf(decodeByte(a), decodeByte(b))
    }

    private fun parseMilStatus(hex: List<Int>): Status? {
        val modeIdx = hex.indexOfFirst { it == 0x41 }
        val start = if (modeIdx >= 0) modeIdx else 0
        if (start + 5 >= hex.size) return null
        val a = hex[start + 2]
        val b = hex[start + 3]
        val c = hex[start + 4]
        val d = hex[start + 5]
        val milOn = a and 0x80 != 0
        val dtcCount = a and 0x7F
        val monitors = listOf(
            ReadinessMonitor("Misfire", supported = true, ready = b and 0x10 == 0),
            ReadinessMonitor("Fuel System", supported = true, ready = b and 0x20 == 0),
            ReadinessMonitor("Comprehensive Components", supported = true, ready = b and 0x40 == 0),
            ReadinessMonitor("Catalyst", supported = c and 0x01 != 0, ready = d and 0x01 == 0),
            ReadinessMonitor("Heated Catalyst", supported = c and 0x02 != 0, ready = d and 0x02 == 0),
            ReadinessMonitor("Evaporative System", supported = c and 0x04 != 0, ready = d and 0x04 == 0),
            ReadinessMonitor("Secondary Air System", supported = c and 0x08 != 0, ready = d and 0x08 == 0),
            ReadinessMonitor("O2 Sensor", supported = c and 0x20 != 0, ready = d and 0x20 == 0),
            ReadinessMonitor("O2 Heater", supported = c and 0x40 != 0, ready = d and 0x40 == 0),
            ReadinessMonitor("EGR/VVT", supported = c and 0x80 != 0, ready = d and 0x80 == 0),
        )
        return Status(milOn = milOn, dtcCount = dtcCount, monitors = monitors)
    }

    private fun parseTroubleCodes(hex: List<Int>): List<TroubleCodeMetadata> {
        val modeIdx = hex.indexOfFirst { it == 0x43 }
        if (modeIdx < 0) return emptyList()
        val payload = hex.drop(modeIdx + 1)
        if (payload.isEmpty()) return emptyList()
        val count = payload.first().coerceAtMost((payload.size - 1) / 2)
        if (count <= 0) return emptyList()
        val codes = mutableListOf<TroubleCodeMetadata>()
        for (i in 0 until count) {
            val offset = 1 + i * 2
            if (offset + 1 >= payload.size) break
            val a = payload[offset]
            val b = payload[offset + 1]
            val letter = when ((a and 0xC0) shr 6) {
                0 -> 'P'
                1 -> 'C'
                2 -> 'B'
                else -> 'U'
            }
            val d1 = (a and 0x30) shr 4
            val d2 = a and 0x0F
            val d3 = (b and 0xF0) shr 4
            val d4 = b and 0x0F
            val code = "$letter$d1${d2.toString(16)}${d3.toString(16)}${d4.toString(16)}".uppercase()
            val enriched = TroubleCodeCatalog.lookup(code)
            codes += enriched ?: TroubleCodeMetadata(code = code, severity = "Moderate")
        }
        return codes
    }

    private fun parseHexBytes(lines: List<String>): List<Int> {
        val out = mutableListOf<Int>()
        for (raw in lines) {
            val line = raw.trim().uppercase()
            if (line.isEmpty()) continue
            if (line.contains("SEARCHING") || line.contains("NO DATA") || line.contains("OK") || line.contains("ELM")) {
                continue
            }

            val tokens = if (line.contains(' ')) {
                line.split(Regex("\\s+"))
            } else {
                listOf(line)
            }

            for (token in tokens) {
                val hex = token.filter { it.isDigit() || it in 'A'..'F' }
                if (hex.length < 2) continue
                if (hex.length == 2) {
                    hex.toIntOrNull(16)?.let(out::add)
                    continue
                }

                // Handle compact CAN frames from some adapters (e.g., "7E804410C393C").
                var payload = hex
                if (payload.length % 2 == 1 && payload.length >= 5) {
                    payload = payload.drop(3) // Drop 3-char CAN header (e.g., 7E8).
                }
                if (payload.length < 2) continue
                if (payload.length % 2 == 1) {
                    payload = payload.drop(1)
                }
                for (i in 0 until payload.length step 2) {
                    payload.substring(i, i + 2).toIntOrNull(16)?.let(out::add)
                }
            }
        }
        return out
    }

    private fun parsePidMeasurement(pid: String, hex: List<Int>): MeasurementResult? {
        if (hex.size < 2) return null
        val modeIdx = hex.indexOfFirst { it == 0x41 }
        val start = if (modeIdx >= 0) modeIdx else 0
        if (start + 2 >= hex.size) return null
        val responsePid = "%02X".format(hex[start + 1])
        if (!pid.endsWith(responsePid)) return null
        return when (pid) {
            "010C" -> {
                if (start + 3 >= hex.size) return null
                val rpm = ((hex[start + 2] * 256 + hex[start + 3]) / 4.0)
                MeasurementResult(rpm, "RPM")
            }
            "0105" -> MeasurementResult(hex[start + 2] - 40.0, "°C")
            "0142" -> {
                if (start + 3 >= hex.size) return null
                val volts = (hex[start + 2] * 256 + hex[start + 3]) / 1000.0
                MeasurementResult(volts, "V")
            }
            "010F" -> MeasurementResult(hex[start + 2] - 40.0, "°C")
            "010D" -> MeasurementResult(hex[start + 2].toDouble(), "km/h")
            else -> null
        }
    }
}
