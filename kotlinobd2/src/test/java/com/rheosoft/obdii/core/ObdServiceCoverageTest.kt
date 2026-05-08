package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.ble.BleCharacteristic
import com.rheosoft.obdii.core.communication.ble.BlePeripheral
import com.rheosoft.obdii.core.communication.ble.BlePlatformAdapter
import com.rheosoft.obdii.core.communication.ble.BleService
import com.rheosoft.obdii.core.protocols.UnsupportedTransportError
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ObdServiceCoverageTest {

    @Test
    fun defaultServiceStartsDisconnectedInDemoMode() {
        val service = ObdService()

        assertEquals(LibraryConnectionType.demo, service.currentConnectionType.value)
        assertEquals(AdapterConnectionState.disconnected, service.connectionState.value)
        assertNull(service.connectedPeripheral)
    }

    @Test
    fun demoStartSendScanAndStopFlow() = runBlocking {
        val service = ObdService(LibraryConnectionType.demo)

        service.startConnection(timeoutMs = 1)
        val response = service.sendCommand("010C")
        val peripherals = service.scanForPeripherals()
        service.stopConnection()

        assertTrue(response.any { it.contains("41 0C") })
        assertEquals(emptyList(), peripherals)
        assertEquals(AdapterConnectionState.disconnected, service.connectionState.value)
        assertNull(service.connectedPeripheral)
    }

    @Test
    fun switchConnectionTypeNoOpsForSameTypeHostAndPort() {
        val service = ObdService(
            connectionType = LibraryConnectionType.wifi,
            wifiHost = "127.0.0.1",
            wifiPort = 35000,
        )

        service.switchConnectionType(LibraryConnectionType.wifi, host = "127.0.0.1", port = 35000)

        assertEquals(LibraryConnectionType.wifi, service.currentConnectionType.value)
        assertEquals(AdapterConnectionState.disconnected, service.connectionState.value)
    }

    @Test
    fun switchConnectionTypeUpdatesTypeAndState() {
        val service = ObdService(LibraryConnectionType.demo)

        service.switchConnectionType(LibraryConnectionType.wifi, host = "127.0.0.1", port = 35001)
        assertEquals(LibraryConnectionType.wifi, service.currentConnectionType.value)

        service.switchConnectionType(LibraryConnectionType.demo)
        assertEquals(LibraryConnectionType.demo, service.currentConnectionType.value)
    }

    @Test
    fun unsupportedBluetoothStartSetsErrorAndThrows() = runBlocking {
        val service = ObdService(LibraryConnectionType.bluetooth)

        assertFailsWith<UnsupportedTransportError> {
            service.startConnection(timeoutMs = 1)
        }

        assertEquals(AdapterConnectionState.error, service.connectionState.value)
        assertNull(service.connectedPeripheral)
    }

    @Test
    fun fakeBleAdapterSupportsScanAndStartConnection() = runBlocking {
        val adapter = FakeBleAdapter(
            discovered = listOf(
                BlePeripheral("low", "Headphones", rssi = -20),
                BlePeripheral("obd", "VLINK OBD", rssi = -70),
            ),
        )
        val service = ObdService(
            connectionType = LibraryConnectionType.bluetooth,
            bleAdapter = adapter,
        )

        val peripherals = service.scanForPeripherals()
        service.startConnection(timeoutMs = 1)

        assertEquals(listOf("low", "obd"), peripherals.map { it.id })
        assertEquals(listOf("obd"), adapter.connectedIds)
        assertTrue(adapter.commands.contains("ATZ"))
        assertTrue(adapter.commands.contains("ATST64"))
        assertEquals(AdapterConnectionState.connectedToAdapter, service.connectionState.value)
    }

    @Test
    fun setBleAdapterNoOpsForSameAdapterAndRecreatesBluetoothTransportForNewAdapter() = runBlocking {
        val first = FakeBleAdapter(listOf(BlePeripheral("first", "OBD One", rssi = -60)))
        val second = FakeBleAdapter(listOf(BlePeripheral("second", "OBD Two", rssi = -50)))
        val service = ObdService(
            connectionType = LibraryConnectionType.bluetooth,
            bleAdapter = first,
        )

        service.setBleAdapter(first)
        assertEquals(listOf("first"), service.scanForPeripherals().map { it.id })

        service.setBleAdapter(second)
        assertEquals(listOf("second"), service.scanForPeripherals().map { it.id })
    }

    @Test
    fun connectionStateChangedClearsPeripheralForTerminalStates() {
        val service = ObdService(LibraryConnectionType.demo)

        service.connectionStateChanged(AdapterConnectionState.connectedToAdapter)
        assertEquals(AdapterConnectionState.connectedToAdapter, service.connectionState.value)

        service.connectionStateChanged(AdapterConnectionState.error)
        assertEquals(AdapterConnectionState.error, service.connectionState.value)
        assertNull(service.connectedPeripheral)

        service.connectionStateChanged(AdapterConnectionState.disconnected)
        assertEquals(AdapterConnectionState.disconnected, service.connectionState.value)
        assertNull(service.connectedPeripheral)
    }

    private class FakeBleAdapter(
        private val discovered: List<BlePeripheral>,
    ) : BlePlatformAdapter {
        val connectedIds = mutableListOf<String>()
        val commands = mutableListOf<String>()
        private var listener: ((ByteArray) -> Unit)? = null

        override suspend fun scan(timeoutMs: Long, serviceUuids: Set<String>): List<BlePeripheral> = discovered

        override suspend fun connect(peripheralId: String, timeoutMs: Long) {
            connectedIds += peripheralId
        }

        override suspend fun disconnect(peripheralId: String) = Unit

        override suspend fun discoverServices(peripheralId: String): List<BleService> =
            listOf(BleService("FFE0"))

        override suspend fun discoverCharacteristics(
            peripheralId: String,
            serviceUuid: String,
        ): List<BleCharacteristic> =
            listOf(BleCharacteristic("FFE1", canRead = true, canWrite = true, canNotify = true))

        override suspend fun enableNotifications(peripheralId: String, characteristicUuid: String) = Unit

        override suspend fun write(peripheralId: String, characteristicUuid: String, payload: ByteArray) {
            val command = payload.toString(Charsets.US_ASCII).trim()
            commands += command
            val response = when (command) {
                "ATZ" -> "ELM327 v1.5\r>"
                else -> "OK\r>"
            }
            listener?.invoke(response.toByteArray(Charsets.US_ASCII))
        }

        override fun setNotificationListener(
            peripheralId: String,
            characteristicUuid: String,
            listener: (ByteArray) -> Unit,
        ) {
            this.listener = listener
        }
    }
}
