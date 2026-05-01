package com.rheosoft.obdii.core

enum class LibraryConnectionType {
    bluetooth,
    wifi,
    demo,
}

enum class AdapterConnectionState {
    disconnected,
    connecting,
    connectedToAdapter,
    connectedToVehicle,
    error,
}

data class PeripheralInfo(
    val id: String,
    val name: String? = null,
)

interface OBDServiceDelegate {
    fun connectionStateChanged(state: AdapterConnectionState)
}
