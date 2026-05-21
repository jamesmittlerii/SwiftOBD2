package com.rheosoft.obdii.core.communication.ble

/** Last BLE peripheral that connected successfully; used for faster scan/connect on Windows WinRT. */
object BleScanPreferences {
    @Volatile
    var preferredPeripheralId: String? = null
}
