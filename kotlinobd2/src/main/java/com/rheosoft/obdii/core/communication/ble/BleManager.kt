package com.rheosoft.obdii.core.communication.ble

import com.rheosoft.obdii.core.AdapterConnectionState
import com.rheosoft.obdii.core.LogCategory
import com.rheosoft.obdii.core.OBDServiceDelegate
import com.rheosoft.obdii.core.PeripheralInfo
import com.rheosoft.obdii.core.obdDebug
import com.rheosoft.obdii.core.obdError
import com.rheosoft.obdii.core.obdInfo
import com.rheosoft.obdii.core.obdWarning
import com.rheosoft.obdii.core.protocols.CommProtocol
import com.rheosoft.obdii.core.protocols.CommunicationError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

class BleManager(
    private val adapter: BlePlatformAdapter = UnsupportedBleAdapter(),
) : CommProtocol {
    companion object {
        /** Scan budget when connecting; connect timeout may be larger (e.g. 30s). */
        private const val CONNECT_SCAN_TIMEOUT_MS = 10_000L
        /** Flutter parity: delay after ATSP0 before first 0100 during protocol detect. */
        private const val POST_SEARCHING_SETTLE_MS = 1_000L
        private const val RETRY_SETTLE_MS = 500L
    }

    private val commandMutex = Mutex()
    private val stateFlow = MutableStateFlow(AdapterConnectionState.disconnected)
    override val connectionState: StateFlow<AdapterConnectionState> = stateFlow
    override var obdDelegate: OBDServiceDelegate? = null
    private val scanner = BlePeripheralScanner()
    private val processor = BleMessageProcessor()
    private val characteristicHandler = BleCharacteristicHandler(processor)
    private val peripheralManager = BlePeripheralManager(adapter, characteristicHandler)
    private var connectedPeripheral: BlePeripheral? = null

    override suspend fun sendCommand(command: String, retries: Int): List<String> = commandMutex.withLock {
        val target = connectedPeripheral ?: throw CommunicationError("BLE peripheral not connected")
        val write = characteristicHandler.writeCharacteristic ?: throw CommunicationError("BLE write characteristic unavailable")
        var lastError: Throwable? = null
        val attempts = (retries + 1).coerceAtLeast(1)
        repeat(attempts) { attempt ->
            try {
                val pendingResponse = processor.beginResponseWait()
                obdDebug("ble:tx $command", LogCategory.Communication)
                adapter.write(target.id, write.uuid, "$command\r".toByteArray(Charsets.US_ASCII))
                val response = processor.awaitResponse(pendingResponse, timeoutMs = 10_000)
                obdInfo("→ Sent: $command\n← Response: ${response.joinToString(" | ")}", LogCategory.Communication)
                if (response.any { it.contains("SEARCHING", ignoreCase = true) }) {
                    obdDebug(
                        "ble:settle ${POST_SEARCHING_SETTLE_MS}ms after SEARCHING ($command)",
                        LogCategory.Communication,
                    )
                    delay(POST_SEARCHING_SETTLE_MS)
                }
                return@withLock response
            } catch (t: Throwable) {
                processor.failPending(t)
                lastError = t
                if (attempt < attempts - 1) {
                    obdDebug("ble:retry-settle ${RETRY_SETTLE_MS}ms before retry ($command)", LogCategory.Communication)
                    delay(RETRY_SETTLE_MS)
                }
            }
        }
        obdError("Command failed: $command - ${lastError?.message}", LogCategory.Communication)
        throw CommunicationError("BLE send failed", lastError)
    }

    override fun disconnectPeripheral() {
        val peripheral = connectedPeripheral
        connectedPeripheral = null
        peripheralManager.reset()
        if (peripheral != null) {
            obdInfo("Disconnecting from peripheral: ${peripheral.name ?: peripheral.id}", LogCategory.Bluetooth)
            runBlocking(Dispatchers.IO) {
                withTimeoutOrNull(3_000) {
                    runCatching { adapter.disconnect(peripheral.id) }
                }
            }
        }
        stateFlow.value = AdapterConnectionState.disconnected
        obdDelegate?.connectionStateChanged(AdapterConnectionState.disconnected)
    }

    override suspend fun connectAsync(timeoutMs: Long, peripheral: PeripheralInfo?) {
        stateFlow.value = AdapterConnectionState.connecting
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connecting)
        val target = if (peripheral != null) {
            BlePeripheral(id = peripheral.id, name = peripheral.name)
        } else {
            val scanTimeout = minOf(timeoutMs, CONNECT_SCAN_TIMEOUT_MS)
            obdDebug(
                "connect:scan-requested timeoutMs=$scanTimeout (connectTimeoutMs=$timeoutMs) " +
                    "preferredId=${BleScanPreferences.preferredPeripheralId} " +
                    "serviceUuids=$supportedBleServiceUuids",
                LogCategory.Bluetooth,
            )
            val scanStartedAt = System.currentTimeMillis()
            val discovered = adapter.scan(timeoutMs = scanTimeout, serviceUuids = supportedBleServiceUuids)
            obdDebug(
                "connect:scan-finished elapsedMs=${System.currentTimeMillis() - scanStartedAt} " +
                    "found=${discovered.size} ${formatScanResults(discovered)}",
                LogCategory.Bluetooth,
            )
            discovered.forEach(scanner::addDiscoveredPeripheral)
            val selected = selectPreferredPeripheral(discovered)
                ?: throw CommunicationError("No compatible OBD BLE peripheral found")
            obdDebug(
                "connect:scan-selected name=${selected.name ?: "(none)"} id=${selected.id} rssi=${selected.rssi}",
                LogCategory.Bluetooth,
            )
            selected
        }
        
        obdInfo("Attempting connection to peripheral: ${target.name ?: target.id}", LogCategory.Bluetooth)
        var lastConnectError: Throwable? = null
        var connected = false
        for (attempt in 0 until 3) {
            try {
                adapter.connect(target.id, timeoutMs = timeoutMs)
                connected = true
                break
            } catch (t: Throwable) {
                lastConnectError = t
                // Android BLE can intermittently fail early connects with GATT 133.
                runCatching { adapter.disconnect(target.id) }
                if (attempt < 2) delay(800)
            }
        }
        if (!connected && lastConnectError != null) {
            obdError("Connection failed to peripheral: ${target.name ?: target.id} - ${lastConnectError.message}", LogCategory.Bluetooth)
            throw CommunicationError("BLE connect failed", lastConnectError)
        }
        obdInfo("Connected to peripheral: ${target.name ?: target.id}", LogCategory.Bluetooth)
        peripheralManager.setPeripheral(target)
        delay(300)
        connectedPeripheral = target
        stateFlow.value = AdapterConnectionState.connectedToAdapter
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connectedToAdapter)
        val read = characteristicHandler.readCharacteristic?.uuid
        val write = characteristicHandler.writeCharacteristic?.uuid
        obdInfo(
            "Characteristics setup complete, connected to adapter (read=$read write=$write)",
            LogCategory.Bluetooth,
        )
    }

    override suspend fun scanForPeripherals(): List<PeripheralInfo> {
        obdDebug("scanForPeripherals:start timeoutMs=10000", LogCategory.Bluetooth)
        val scanStartedAt = System.currentTimeMillis()
        val discovered = adapter.scan(timeoutMs = 10_000, serviceUuids = supportedBleServiceUuids)
        obdDebug(
            "scanForPeripherals:finished elapsedMs=${System.currentTimeMillis() - scanStartedAt} " +
                "found=${discovered.size} ${formatScanResults(discovered)}",
            LogCategory.Bluetooth,
        )
        discovered.forEach(scanner::addDiscoveredPeripheral)
        return scanner.foundPeripherals.map { PeripheralInfo(id = it.id, name = it.name) }
    }

    private fun selectPreferredPeripheral(discovered: List<BlePeripheral>): BlePeripheral? {
        if (discovered.isEmpty()) return null
        BleScanPreferences.preferredPeripheralId?.let { preferredId ->
            discovered.firstOrNull { it.id.equals(preferredId, ignoreCase = true) }?.let { return it }
        }
        val matchWords = listOf("OBD", "ELM", "VLINK", "VGATE", "BAFX", "KONNWEI")
        val likelyObd = discovered.filter { peripheral ->
            val n = peripheral.name?.uppercase().orEmpty()
            matchWords.any { n.contains(it) }
        }
        if (likelyObd.isNotEmpty()) {
            obdDebug(
                "connect:scan-pick likelyObd=${formatScanResults(likelyObd)}",
                LogCategory.Bluetooth,
            )
            return likelyObd.maxByOrNull { it.rssi ?: Int.MIN_VALUE }
        }
        // Fallback only when there is exactly one named candidate.
        val named = discovered.filter { !it.name.isNullOrBlank() }
        obdDebug(
            "connect:scan-pick noLikelyObd namedCount=${named.size} " +
                if (named.size == 1) "fallback=${named.first().name}" else "fallback=none",
            LogCategory.Bluetooth,
        )
        return if (named.size == 1) named.first() else null
    }

    private fun formatScanResults(peripherals: List<BlePeripheral>): String =
        peripherals.joinToString(prefix = "[", postfix = "]") { p ->
            "${p.name ?: "?"}:${p.id}:rssi=${p.rssi}"
        }

}
