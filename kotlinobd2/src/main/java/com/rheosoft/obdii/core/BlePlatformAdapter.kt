package com.rheosoft.obdii.core

interface BlePlatformAdapter {
    suspend fun scan(timeoutMs: Long, serviceUuids: Set<String>): List<BlePeripheral>
    suspend fun connect(peripheralId: String, timeoutMs: Long)
    suspend fun disconnect(peripheralId: String)
    suspend fun discoverServices(peripheralId: String): List<BleService>
    suspend fun discoverCharacteristics(peripheralId: String, serviceUuid: String): List<BleCharacteristic>
    suspend fun enableNotifications(peripheralId: String, characteristicUuid: String)
    suspend fun write(peripheralId: String, characteristicUuid: String, payload: ByteArray)
    fun setNotificationListener(peripheralId: String, characteristicUuid: String, listener: (ByteArray) -> Unit)
}

class UnsupportedBleAdapter : BlePlatformAdapter {
    override suspend fun scan(timeoutMs: Long, serviceUuids: Set<String>): List<BlePeripheral> =
        throw UnsupportedTransportError("BLE")

    override suspend fun connect(peripheralId: String, timeoutMs: Long) = throw UnsupportedTransportError("BLE")
    override suspend fun disconnect(peripheralId: String) = Unit
    override suspend fun discoverServices(peripheralId: String): List<BleService> = throw UnsupportedTransportError("BLE")
    override suspend fun discoverCharacteristics(peripheralId: String, serviceUuid: String): List<BleCharacteristic> =
        throw UnsupportedTransportError("BLE")

    override suspend fun enableNotifications(peripheralId: String, characteristicUuid: String) =
        throw UnsupportedTransportError("BLE")

    override suspend fun write(peripheralId: String, characteristicUuid: String, payload: ByteArray) =
        throw UnsupportedTransportError("BLE")

    override fun setNotificationListener(peripheralId: String, characteristicUuid: String, listener: (ByteArray) -> Unit) = Unit
}
