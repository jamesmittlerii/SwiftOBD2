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

object ObdConnectionLibrary : PidStatsProviding, DiagnosticsProviding, FuelStatusProviding, MilStatusProviding, OBDConnectionControlling {
    override val connectionState: OBDConnectionState get() = _connectionState
    private var _connectionState = OBDConnectionState.disconnected
    
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

    private val connFlow = MutableStateFlow(_connectionState)
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
    private val defaultPids = setOf("010C", "0105", "0142", "010F", "010D", "0101", "0103", "0144")
    
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
        if (_connectionState == OBDConnectionState.connected || _connectionState == OBDConnectionState.connecting) return
        _connectionState = OBDConnectionState.connecting
        connFlow.value = _connectionState
        try {
            service.startConnection(timeoutMs = 20_000)
            _connectionState = OBDConnectionState.connected
            connFlow.value = _connectionState
            connectedPeripheralName = service.connectedPeripheral?.name
            startPolling()
        } catch (t: Throwable) {
            _connectionState = OBDConnectionState.failed
            connFlow.value = _connectionState
            throw t
        }
    }

    override fun disconnect() {
        pollJob?.cancel()
        pollJob = null
        service.stopConnection()
        clearForTerminalState()
        _connectionState = OBDConnectionState.disconnected
        connFlow.value = _connectionState
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
        _connectionState = OBDConnectionState.disconnected
        connFlow.value = _connectionState
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
                _connectionState = OBDConnectionState.disconnected
                connFlow.value = _connectionState
            }
            AdapterConnectionState.error -> {
                clearForTerminalState()
                _connectionState = OBDConnectionState.failed
                connFlow.value = _connectionState
            }
            AdapterConnectionState.connecting -> {
                if (_connectionState != OBDConnectionState.connecting) {
                    _connectionState = OBDConnectionState.connecting
                    connFlow.value = _connectionState
                }
            }
            AdapterConnectionState.connectedToAdapter,
            AdapterConnectionState.connectedToVehicle,
            -> {
                if (_connectionState != OBDConnectionState.connected) {
                    _connectionState = OBDConnectionState.connected
                    connFlow.value = _connectionState
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
            while (isActive && _connectionState == OBDConnectionState.connected) {
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
        val hex = Parser.parseHexBytes(lines)
        if (hex.isEmpty()) return

        // Use the new CommandCatalog and OBDCommand structure
        val command = if (pid == "03") OBDCommand.Mode3() else OBDCommand.Mode1(pid.takeLast(2))
        val result = command.properties.decode(hex)
        println("PID $pid, hex $hex, command ${command.properties.command}, decoder ${command.properties.decoder}, result $result")

        when (result) {
            is DecodeResult.Measurement -> {
                val measurement = result.value
                val existing = statsAccumulator[pid]
                statsAccumulator[pid] = existing?.copyWith(measurement) ?: PIDStats(pid, measurement)
            }
            is DecodeResult.StatusResult -> {
                milStatus = result.value
                milFlow.value = milStatus
            }
            is DecodeResult.TroubleCodes -> {
                troubleCodes = result.codes
                diagnosticsFlow.value = troubleCodes
            }
            is DecodeResult.FuelStatusResult -> {
                fuelStatus = result.status
                fuelFlow.value = fuelStatus
            }
            is DecodeResult.Failure -> {
                // Log failure if needed
            }
        }
    }
}
