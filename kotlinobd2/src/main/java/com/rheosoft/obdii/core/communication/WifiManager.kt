package com.rheosoft.obdii.core.communication

import com.rheosoft.obdii.core.AdapterConnectionState
import com.rheosoft.obdii.core.OBDServiceDelegate
import com.rheosoft.obdii.core.PeripheralInfo
import com.rheosoft.obdii.core.protocols.CommProtocol
import com.rheosoft.obdii.core.protocols.CommunicationError
import com.rheosoft.obdii.core.protocols.ConnectionTimedOutError
import com.rheosoft.obdii.core.protocols.InvalidDataError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.PrintWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException

class WifiManager(
    private val host: String,
    private val port: Int,
) : CommProtocol {
    private val stateFlow = MutableStateFlow(AdapterConnectionState.disconnected)
    override val connectionState: StateFlow<AdapterConnectionState> = stateFlow
    override var obdDelegate: OBDServiceDelegate? = null

    private var socket: Socket? = null
    private var writer: PrintWriter? = null
    private var reader: BufferedReader? = null

    override suspend fun connectAsync(timeoutMs: Long, peripheral: PeripheralInfo?): Unit = withContext(Dispatchers.IO) {
        stateFlow.value = AdapterConnectionState.connecting
        obdDelegate?.connectionStateChanged(AdapterConnectionState.connecting)
        try {
            val s = Socket()
            s.connect(InetSocketAddress(host, port), timeoutMs.toInt())
            s.soTimeout = timeoutMs.toInt().coerceAtLeast(2_000)
            socket = s
            writer = PrintWriter(s.getOutputStream(), true)
            reader = BufferedReader(InputStreamReader(s.getInputStream()))
            stateFlow.value = AdapterConnectionState.connectedToAdapter
            obdDelegate?.connectionStateChanged(AdapterConnectionState.connectedToAdapter)
        } catch (e: SocketTimeoutException) {
            stateFlow.value = AdapterConnectionState.error
            obdDelegate?.connectionStateChanged(AdapterConnectionState.error)
            throw ConnectionTimedOutError()
        } catch (e: Exception) {
            stateFlow.value = AdapterConnectionState.error
            obdDelegate?.connectionStateChanged(AdapterConnectionState.error)
            throw CommunicationError("WiFi connect failed", e)
        }
    }

    override suspend fun sendCommand(command: String, retries: Int): List<String> = withContext(Dispatchers.IO) {
        var lastError: Throwable? = null
        repeat((retries + 1).coerceAtLeast(1)) {
            try {
                val localWriter = writer ?: throw CommunicationError("No active socket writer")
                val localReader = reader ?: throw CommunicationError("No active socket reader")
                localWriter.print("$command\r")
                localWriter.flush()

                val result = StringBuilder()
                while (true) {
                    val ch = localReader.read()
                    if (ch == -1) break
                    val c = ch.toChar()
                    result.append(c)
                    if (c == '>') break
                }
                val lines = result.toString()
                    .replace(">", "")
                    .split('\r', '\n')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                if (lines.isEmpty()) throw InvalidDataError()
                return@withContext lines
            } catch (e: Throwable) {
                lastError = e
            }
        }
        throw CommunicationError("WiFi send failed", lastError)
    }

    override fun disconnectPeripheral() {
        try {
            reader?.close()
            writer?.close()
            socket?.close()
        } finally {
            reader = null
            writer = null
            socket = null
            stateFlow.value = AdapterConnectionState.disconnected
            obdDelegate?.connectionStateChanged(AdapterConnectionState.disconnected)
        }
    }

    override suspend fun scanForPeripherals(): List<PeripheralInfo> = emptyList()
}
