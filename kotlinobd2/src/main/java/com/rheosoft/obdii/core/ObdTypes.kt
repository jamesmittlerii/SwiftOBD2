package com.rheosoft.obdii.core

import kotlinx.coroutines.flow.StateFlow

data class MeasurementResult(val value: Double, val unit: String)

data class TroubleCodeMetadata(
    val code: String,
    val title: String = "",
    val description: String = "",
    val severity: String = "",
    val causes: List<String> = emptyList(),
    val remedies: List<String> = emptyList(),
)

data class StatusCodeMetadata(val code: String, val description: String)

data class ReadinessMonitor(val name: String, val supported: Boolean, val ready: Boolean)

data class Status(val milOn: Boolean, val dtcCount: Int, val monitors: List<ReadinessMonitor> = emptyList())

data class PIDStats(
    val pid: String,
    val latest: MeasurementResult,
    val min: Double = latest.value,
    val max: Double = latest.value,
    val sampleCount: Int = 1,
) {
    fun copyWith(measurement: MeasurementResult): PIDStats = copy(
        latest = measurement,
        min = kotlin.math.min(min, measurement.value),
        max = kotlin.math.max(max, measurement.value),
        sampleCount = sampleCount + 1,
    )
}

interface PidStatsProviding {
    val pidStats: Map<String, PIDStats>
    fun statsFor(pidCommand: String): PIDStats?
    val pidStatsStream: StateFlow<Map<String, PIDStats>>
}

interface DiagnosticsProviding {
    val troubleCodes: List<TroubleCodeMetadata>?
    val diagnosticsStream: StateFlow<List<TroubleCodeMetadata>?>
}

interface FuelStatusProviding {
    val fuelStatus: List<StatusCodeMetadata?>?
    val fuelStatusStream: StateFlow<List<StatusCodeMetadata?>?>
}

interface MilStatusProviding {
    val milStatus: Status?
    val milStatusStream: StateFlow<Status?>
}

interface OBDConnectionControlling {
    val connectionState: OBDConnectionState
    fun updateConnectionDetails()
    suspend fun connect()
    fun disconnect()
    val connectionStateStream: StateFlow<OBDConnectionState>
}
