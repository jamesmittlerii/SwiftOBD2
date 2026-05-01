package com.rheosoft.obdii.core.communication.ble

data class BlePeripheral(
    val id: String,
    val name: String?,
    val rssi: Int? = null,
)

data class BleService(
    val uuid: String,
)

data class BleCharacteristic(
    val uuid: String,
    val canRead: Boolean = false,
    val canWrite: Boolean = false,
    val canNotify: Boolean = false,
)

val supportedBleServiceUuids: Set<String> = setOf(
    "FFE0",
    "FFF0",
    "18F0",
    "FFC0",
    "6E400001B5A3F393E0A9E50E24DCCA9E",
)
