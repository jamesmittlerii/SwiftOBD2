package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.protocols.CommProtocol
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow

class Elm327(
    private val comm: CommProtocol,
) {
    var obdDelegate: OBDServiceDelegate? = null
        set(value) {
            field = value
            comm.obdDelegate = value
        }

    val connectionState: StateFlow<AdapterConnectionState> = comm.connectionState

    suspend fun connectToAdapter(timeoutMs: Long, peripheral: PeripheralInfo? = null) {
        comm.connectAsync(timeoutMs = timeoutMs, peripheral = peripheral)
    }

    suspend fun adapterInitialization() {
        obdInfo("Initializing ELM327 adapter...", LogCategory.Connection)
        try {
            sendCommand("ATZ")
            // Swift parity: allow adapter reset to complete before next command.
            delay(300)
            sendCommand("ATE0")
            sendCommand("ATS0")
            sendCommand("ATL0")
            sendCommand("ATH1")
            sendCommand("ATSP0")
            sendCommand("ATAT1")
            sendCommand("ATAL")
            // Keep startup detection tolerant while the ELM is finding a protocol.
            sendCommand("ATST64")
            obdInfo("ELM327 adapter initialized successfully.", LogCategory.Connection)
        } catch (t: Throwable) {
            obdError("Adapter initialization failed: ${t.message}", LogCategory.Connection)
            throw t
        }
    }

    suspend fun sendCommand(message: String, retries: Int = 1): List<String> = comm.sendCommand(message, retries)

    suspend fun scanForPeripherals(): List<PeripheralInfo> = comm.scanForPeripherals()

    fun stopConnection() {
        comm.disconnectPeripheral()
    }
}
