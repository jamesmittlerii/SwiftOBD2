package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.WifiManager
import com.rheosoft.obdii.core.protocols.CommunicationError
import com.rheosoft.obdii.core.protocols.ConnectionTimedOutError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Test
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class WifiManagerCoverageTest {

    @Test
    fun connectsSendsParsesPromptAndDisconnects() = runBlocking {
        withLoopbackServer { server, sockets ->
            val received = CopyOnWriteArrayList<String>()
            val acceptJob = async(Dispatchers.IO) {
                val socket = server.accept()
                sockets += socket
                val input = socket.getInputStream()
                val output = socket.getOutputStream()
                val command = readUntilCarriageReturn(input)
                received += command
                output.write("\r\n$command\r\n7E8 03 41 0D 28\r\n\r\n>".toByteArray())
                output.flush()
            }
            val manager = WifiManager(InetAddress.getLoopbackAddress().hostAddress, server.localPort)
            val states = mutableListOf<AdapterConnectionState>()
            manager.obdDelegate = object : OBDServiceDelegate {
                override fun connectionStateChanged(state: AdapterConnectionState) {
                    states += state
                }
            }

            manager.connectAsync(timeoutMs = 1_000)
            val response = manager.sendCommand("010D")
            manager.disconnectPeripheral()
            acceptJob.await()

            assertEquals(listOf("010D"), received.toList())
            assertEquals(listOf("010D", "7E8 03 41 0D 28"), response)
            assertEquals(AdapterConnectionState.disconnected, manager.connectionState.value)
            assertTrue(states.contains(AdapterConnectionState.connecting))
            assertTrue(states.contains(AdapterConnectionState.connectedToAdapter))
            assertTrue(states.contains(AdapterConnectionState.disconnected))
        }
    }

    @Test
    fun sendCommandWithoutSocketThrowsCommunicationError() = runBlocking {
        val manager = WifiManager("127.0.0.1", 9)

        assertFailsWith<CommunicationError> {
            manager.sendCommand("010C", retries = 0)
        }
    }

    @Test
    fun retriesAfterEmptyResponseAndThenSucceeds() = runBlocking {
        withLoopbackServer { server, sockets ->
            val acceptJob = async(Dispatchers.IO) {
                val socket = server.accept()
                sockets += socket
                val input = socket.getInputStream()
                val output = socket.getOutputStream()

                readUntilCarriageReturn(input)
                output.write(">".toByteArray())
                output.flush()

                readUntilCarriageReturn(input)
                output.write("7E8 04 41 0C 0C 80\r>".toByteArray())
                output.flush()
            }
            val manager = WifiManager(InetAddress.getLoopbackAddress().hostAddress, server.localPort)

            manager.connectAsync(timeoutMs = 1_000)
            val response = manager.sendCommand("010C", retries = 1)
            manager.disconnectPeripheral()
            acceptJob.await()

            assertEquals(listOf("7E8 04 41 0C 0C 80"), response)
        }
    }

    @Test
    fun connectionRefusalEmitsErrorAndThrowsCommunicationError() = runBlocking {
        val closedServer = ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        val port = closedServer.localPort
        closedServer.close()
        val manager = WifiManager(InetAddress.getLoopbackAddress().hostAddress, port)
        val states = mutableListOf<AdapterConnectionState>()
        manager.obdDelegate = object : OBDServiceDelegate {
            override fun connectionStateChanged(state: AdapterConnectionState) {
                states += state
            }
        }

        assertFailsWith<CommunicationError> {
            manager.connectAsync(timeoutMs = 250)
        }
        assertEquals(AdapterConnectionState.error, manager.connectionState.value)
        assertTrue(states.contains(AdapterConnectionState.connecting))
        assertTrue(states.contains(AdapterConnectionState.error))
    }

    @Test
    fun connectionTimeoutMapsToConnectionTimedOutError() = runBlocking {
        val manager = WifiManager("203.0.113.1", 35000)

        assertFailsWith<ConnectionTimedOutError> {
            manager.connectAsync(timeoutMs = 50)
        }
        assertEquals(AdapterConnectionState.error, manager.connectionState.value)
    }

    @Test
    fun scanForPeripheralsReturnsEmptyList() = runBlocking {
        val manager = WifiManager("127.0.0.1", 35000)

        assertEquals(emptyList(), manager.scanForPeripherals())
    }

    private suspend fun withLoopbackServer(
        block: suspend (ServerSocket, MutableList<Socket>) -> Unit,
    ) {
        val sockets = mutableListOf<Socket>()
        val server = withContext(Dispatchers.IO) {
            ServerSocket(0, 1, InetAddress.getLoopbackAddress())
        }
        try {
            block(server, sockets)
        } finally {
            sockets.forEach { runCatching { it.close() } }
            withContext(Dispatchers.IO) { server.close() }
        }
    }

    private fun readUntilCarriageReturn(input: java.io.InputStream): String {
        val bytes = mutableListOf<Byte>()
        while (true) {
            val next = input.read()
            if (next == -1 || next.toChar() == '\r') break
            bytes += next.toByte()
        }
        return bytes.toByteArray().toString(Charsets.US_ASCII)
    }
}
