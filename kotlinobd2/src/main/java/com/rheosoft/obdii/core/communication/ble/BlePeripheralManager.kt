package com.rheosoft.obdii.core.communication.ble

import com.rheosoft.obdii.core.protocols.CommunicationError

class BlePeripheralManager(
    private val adapter: BlePlatformAdapter,
    private val handler: BleCharacteristicHandler,
) {
    var connectedPeripheral: BlePeripheral? = null
        private set

    suspend fun setPeripheral(peripheral: BlePeripheral) {
        connectedPeripheral = peripheral
        val services = adapter.discoverServices(peripheral.id)
        for (service in services) {
            val chars = adapter.discoverCharacteristics(peripheral.id, service.uuid)
            handler.setupCharacteristics(chars)
        }
        val read = handler.readCharacteristic ?: throw CommunicationError("BLE read characteristic not found")
        if (read.canNotify) {
            adapter.enableNotifications(peripheral.id, read.uuid)
        }
        adapter.setNotificationListener(peripheral.id, read.uuid) { payload ->
            handler.handleUpdatedValue(payload)
        }
        if (!handler.isReady) throw CommunicationError("BLE characteristic setup incomplete")
    }

    fun reset() {
        connectedPeripheral = null
        handler.reset()
    }
}
