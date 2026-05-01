package com.rheosoft.obdii.core.communication.ble

import kotlinx.coroutines.withTimeout

class BlePeripheralScanner {
    private val found = linkedMapOf<String, BlePeripheral>()
    val foundPeripherals: List<BlePeripheral>
        get() = found.values.toList()

    fun addDiscoveredPeripheral(peripheral: BlePeripheral) {
        if ((peripheral.rssi ?: -200) >= 0) return
        found[peripheral.id] = peripheral
    }

    suspend fun waitForFirstPeripheral(timeoutMs: Long): BlePeripheral {
        return withTimeout(timeoutMs) {
            while (found.isEmpty()) {
                kotlinx.coroutines.delay(100)
            }
            found.values.first()
        }
    }
}
