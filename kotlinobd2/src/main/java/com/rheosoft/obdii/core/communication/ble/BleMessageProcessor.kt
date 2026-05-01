package com.rheosoft.obdii.core.communication.ble

import com.rheosoft.obdii.core.protocols.CommunicationError
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout

class BleMessageProcessor {
    private val buffer = StringBuilder()
    private var pending: CompletableDeferred<List<String>>? = null

    fun processReceivedData(data: ByteArray) {
        val chunk = data.toString(Charsets.UTF_8)
        buffer.append(chunk)
        flushIfComplete()
    }

    fun beginResponseWait(): CompletableDeferred<List<String>> {
        check(pending == null) { "Concurrent BLE command detected" }
        val deferred = CompletableDeferred<List<String>>()
        pending = deferred
        // If a full response already landed before beginResponseWait, consume it now.
        flushIfComplete()
        return deferred
    }

    suspend fun awaitResponse(
        deferred: CompletableDeferred<List<String>>,
        timeoutMs: Long,
    ): List<String> = withTimeout(timeoutMs) { deferred.await() }

    fun failPending(cause: Throwable) {
        pending?.completeExceptionally(cause)
        pending = null
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
        if (!buffer.contains(">")) return
        val lines = buffer.toString()
            .replace(">", "")
            .split('\r', '\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        buffer.clear()
        pending?.complete(lines)
        pending = null
    }
}
