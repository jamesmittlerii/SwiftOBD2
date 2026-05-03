package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import com.rheosoft.obdii.core.communication.WifiManager
import com.rheosoft.obdii.core.communication.ble.BleManager
import com.rheosoft.obdii.core.communication.ble.BlePlatformAdapter
import com.rheosoft.obdii.core.communication.ble.UnsupportedBleAdapter
import com.rheosoft.obdii.core.protocols.UnsupportedTransportError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class ObdService(
    connectionType: LibraryConnectionType = LibraryConnectionType.demo,
    private var wifiHost: String = "192.168.0.10",
    private var wifiPort: Int = 35000,
    private var bleAdapter: BlePlatformAdapter = UnsupportedBleAdapter(),
) : OBDServiceDelegate {
    private val _connectionState = MutableStateFlow(AdapterConnectionState.disconnected)
    val connectionState: StateFlow<AdapterConnectionState> = _connectionState.asStateFlow()

    private val _connectionType = MutableStateFlow(connectionType)
    val currentConnectionType: StateFlow<LibraryConnectionType> = _connectionType.asStateFlow()

    private var elm327: Elm327 = createElm327(connectionType)
    var connectedPeripheral: PeripheralInfo? = null
        private set

    private fun createElm327(type: LibraryConnectionType): Elm327 {
        val comm = when (type) {
            LibraryConnectionType.bluetooth -> BleManager(adapter = bleAdapter)
            LibraryConnectionType.wifi -> WifiManager(wifiHost, wifiPort)
            LibraryConnectionType.demo -> MockComm()
        }
        return Elm327(comm).also { it.obdDelegate = this }
    }

    override fun connectionStateChanged(state: AdapterConnectionState) {
        _connectionState.value = state
        if (state == AdapterConnectionState.disconnected || state == AdapterConnectionState.error) {
            connectedPeripheral = null
        }
    }

    fun switchConnectionType(type: LibraryConnectionType, host: String? = null, port: Int? = null) {
        if (host != null) wifiHost = host
        if (port != null) wifiPort = port
        elm327.stopConnection()
        _connectionType.value = type
        elm327 = createElm327(type)
    }

    fun setBleAdapter(adapter: BlePlatformAdapter) {
        bleAdapter = adapter
        if (_connectionType.value == LibraryConnectionType.bluetooth) {
            elm327.stopConnection()
            elm327 = createElm327(LibraryConnectionType.bluetooth)
        }
    }

    suspend fun startConnection(timeoutMs: Long = 30_000, peripheral: PeripheralInfo? = null) {
        try {
            if (_connectionType.value == LibraryConnectionType.bluetooth && bleAdapter is UnsupportedBleAdapter) {
                throw UnsupportedTransportError("BLE")
            }
            elm327.connectToAdapter(timeoutMs = timeoutMs, peripheral = peripheral)
            elm327.adapterInitialization()
            // We stay in connectedToAdapter here.
            // The manager will transition to settingUpVehicle while it queries PIDs.
        } catch (t: Throwable) {
            _connectionState.value = AdapterConnectionState.error
            connectedPeripheral = null
            throw t
        }
    }

    fun stopConnection() {
        elm327.stopConnection()
        _connectionState.value = AdapterConnectionState.disconnected
    }

    suspend fun sendCommand(command: String, retries: Int = 1): List<String> = elm327.sendCommand(command, retries)

    suspend fun scanForPeripherals(): List<PeripheralInfo> = elm327.scanForPeripherals()
}
