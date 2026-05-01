package com.rheosoft.obdii.core.communication.ble

import com.rheosoft.obdii.core.AdapterConnectionState
import com.rheosoft.obdii.core.OBDServiceDelegate
import com.rheosoft.obdii.core.PeripheralInfo
import com.rheosoft.obdii.core.protocols.CommProtocol
import com.rheosoft.obdii.core.protocols.CommunicationError
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.delay

class BleManager(
    private val adapter: BlePlatformAdapter = UnsupportedBleAdapter(),
) : CommProtocol {
    private val stateFlow = MutableStateFlow(AdapterConnectionState.disconnected)
    override val connectionState: StateFlow<AdapterConnectionState> = stateFlow
    override var obdDelegate: OBDServiceDelegate? = null
    private val scanner = BlePeripheralScanner()
    private val processor = BleMessageProcessor()
    private val characteristicHandler = BleCharacteristicHandler(processor)
    private val peripheralManager = BlePeripheralManager(adapter, characteristicHandler)
    private var connectedPeripheral: BlePeripheral? = null

    override suspend fun sendCommand(command: String, retries: Int): List<String> {
        val target = connectedPeripheral ?: throw CommunicationError("BLE peripheral not connected")
        val write = characteristicHandler.writeCharacteristic ?: throw CommunicationError("BLE write characteristic unavailable")
        var lastError: Throwable? = null
        repeat((retries + 1).coerceAtLeast(1)) {
            try {
                val pendingResponse = processor.beginResponseWait()
                adapter.write(target.id, write.uuid, "$command\r".toByteArray(Charsets.US_ASCII))
                return processor.awaitResponse(pendingResponse, timeoutMs = 10_000)
            } catch (t: Throwable) {
                processor.failPending(t)
                lastError = t
            }
        }
        throw CommunicationError("BLE send failed", lastError)
    }

    override fun disconnectPeripheral() {
        connectedPeripheral?.let { peripheral ->
            runCatching { kotlinx.coroutines.runBlocking { adapter.disconnect(peripheral.id) } }
        }
        connectedPeripheral = null
        peripheralManager.reset()
        stateFlow.value = AdapterConnectionState.disconnected
        obdDelegate?.connectionStateChanged(AdapterConnectionState.disconnected)
    }

    override suspend fun connectAsync(timeoutMs: Long, peripheral: PeripheralInfo?) {
        stateFlow.value = AdapterConnectionState.connecting
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connecting)
        val target = if (peripheral != null) {
            BlePeripheral(id = peripheral.id, name = peripheral.name)
        } else {
            val discovered = adapter.scan(timeoutMs = timeoutMs, serviceUuids = supportedBleServiceUuids)
            discovered.forEach(scanner::addDiscoveredPeripheral)
            selectPreferredPeripheral(discovered)
                ?: throw CommunicationError("No compatible OBD BLE peripheral found")
        }
        var lastConnectError: Throwable? = null
        var connected = false
        for (attempt in 0 until 2) {
            try {
                adapter.connect(target.id, timeoutMs = timeoutMs)
                connected = true
                break
            } catch (t: Throwable) {
                lastConnectError = t
                // Android BLE can intermittently fail first connect with GATT 133; retry once.
                runCatching { adapter.disconnect(target.id) }
                if (attempt == 0) delay(600)
            }
        }
        if (!connected && lastConnectError != null) {
            throw CommunicationError("BLE connect failed", lastConnectError)
        }
        peripheralManager.setPeripheral(target)
        connectedPeripheral = target
        stateFlow.value = AdapterConnectionState.connectedToAdapter
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connectedToAdapter)
    }

    override suspend fun scanForPeripherals(): List<PeripheralInfo> {
        val discovered = adapter.scan(timeoutMs = 10_000, serviceUuids = supportedBleServiceUuids)
        discovered.forEach(scanner::addDiscoveredPeripheral)
        return scanner.foundPeripherals.map { PeripheralInfo(id = it.id, name = it.name) }
    }

    private fun selectPreferredPeripheral(discovered: List<BlePeripheral>): BlePeripheral? {
        if (discovered.isEmpty()) return null
        val matchWords = listOf("OBD", "ELM", "VLINK", "VGATE", "BAFX", "KONNWEI")
        val likelyObd = discovered.filter { peripheral ->
            val n = peripheral.name?.uppercase().orEmpty()
            matchWords.any { n.contains(it) }
        }
        if (likelyObd.isNotEmpty()) {
            return likelyObd.maxByOrNull { it.rssi ?: Int.MIN_VALUE }
        }
        // Fallback only when there is exactly one named candidate.
        val named = discovered.filter { !it.name.isNullOrBlank() }
        return if (named.size == 1) named.first() else null
    }
}
