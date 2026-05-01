package com.rheosoft.obdii.core

import kotlinx.coroutines.flow.StateFlow

interface CommProtocol {
    val connectionState: StateFlow<AdapterConnectionState>
    var obdDelegate: OBDServiceDelegate?

    suspend fun sendCommand(command: String, retries: Int = 1): List<String>
    fun disconnectPeripheral()
    suspend fun connectAsync(timeoutMs: Long, peripheral: PeripheralInfo? = null)
    suspend fun scanForPeripherals(): List<PeripheralInfo>
}

open class CommunicationError(message: String, cause: Throwable? = null) : Exception(message, cause)

class ConnectionTimedOutError : CommunicationError("Connection timed out")
class InvalidDataError : CommunicationError("Invalid data")
class UnsupportedTransportError(transport: String) : CommunicationError("$transport transport is not implemented on JVM")
