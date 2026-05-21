package com.rheosoft.obdii.core.communication.ble

import com.rheosoft.obdii.core.LogCategory
import com.rheosoft.obdii.core.ObdLogger
import com.rheosoft.obdii.core.obdDebug
import com.rheosoft.obdii.core.obdWarning
import com.rheosoft.obdii.core.protocols.CommunicationError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout

/**
 * Swift/Flutter parity: append notify chunks until `>`, then return all lines before the prompt.
 * See BLEDataProcessor.swift and base_comm_protocol.dart processStringData.
 */
class BleMessageProcessor {
    private val buffer = StringBuilder()
    private var pending: CompletableDeferred<List<String>>? = null

    fun processReceivedData(data: ByteArray) {
        val chunk = data.toString(Charsets.UTF_8)
        if (ObdLogger.verboseBleComms) {
            obdDebug("ble:rx chunk=${escapeForLog(chunk)}", LogCategory.Communication)
        }
        buffer.append(chunk)
        flushIfComplete()
    }

    suspend fun beginResponseWait(): CompletableDeferred<List<String>> {
        check(pending == null) { "Concurrent BLE command detected" }
        val deferred = CompletableDeferred<List<String>>()
        pending = deferred
        return deferred
    }

    suspend fun awaitResponse(
        deferred: CompletableDeferred<List<String>>,
        timeoutMs: Long,
    ): List<String> = withTimeout(timeoutMs) { deferred.await() }

    fun failPending(cause: Throwable) {
        if (ObdLogger.verboseBleComms && buffer.isNotEmpty()) {
            obdDebug(
                "ble:rx timeout-buffer=${escapeForLog(buffer.toString())}",
                LogCategory.Communication,
            )
        }
        pending?.completeExceptionally(cause)
        pending = null
        buffer.clear()
    }

    suspend fun waitForResponse(timeoutMs: Long): List<String> {
        val deferred = beginResponseWait()
        return awaitResponse(deferred, timeoutMs)
    }

    fun reset() {
        buffer.clear()
        pending?.completeExceptionally(CommunicationError("BLE disconnected"))
        pending = null
    }

    private fun flushIfComplete() {
        val raw = buffer.toString()
        if (!raw.contains(">")) return

        val lines = parseResponseLines(raw)
        if (ObdLogger.verboseBleComms) {
            obdDebug(
                "ble:rx prompt lines=${lines.joinToString(" | ")} pending=${pending != null}",
                LogCategory.Communication,
            )
        }

        val completion = pending
        pending = null
        buffer.clear()

        if (completion == null) {
            obdWarning("ble:rx prompt with no pending command (discarded)", LogCategory.Bluetooth)
            return
        }
        completion.complete(lines)
    }

    private fun parseResponseLines(raw: String): List<String> =
        raw.replace(">", "")
            .split('\r', '\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    private fun escapeForLog(text: String): String =
        text.replace("\\", "\\\\")
            .replace("\r", "\\r")
            .replace("\n", "\\n")
            .replace(">", "\\>")
}
