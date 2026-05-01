package com.rheosoft.obdii.core

enum class MeasurementUnit(val displayName: String) {
    Metric("Metric"),
    Imperial("Imperial");

    val next: MeasurementUnit
        get() = if (this == Metric) Imperial else Metric
}

sealed class DecodeResult {
    data class Measurement(val value: MeasurementResult) : DecodeResult()
    data class StatusResult(val value: Status) : DecodeResult()
    data class TroubleCodes(val codes: List<TroubleCodeMetadata>) : DecodeResult()
    data class FuelStatusResult(val status: List<StatusCodeMetadata?>) : DecodeResult()
    data class Failure(val message: String) : DecodeResult()
}

interface Decoder {
    /**
     * Decodes the raw payload bytes. 
     * The payload should NOT include the service or PID bytes.
     */
    fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult
}

enum class Decoders {
    Temp, Percent, Rpm, Voltage, Speed, Dtc, FuelStatus, Status, Lambda, None;

    fun getDecoder(): Decoder? = when (this) {
        Temp -> TemperatureDecoder()
        Percent -> PercentDecoder()
        Rpm -> RpmDecoder()
        Voltage -> VoltageDecoder()
        Speed -> SpeedDecoder()
        Dtc -> DtcDecoder()
        FuelStatus -> FuelStatusDecoder()
        Status -> StatusDecoder()
        Lambda -> LambdaDecoder()
        None -> null
    }

    companion object {
        fun fromCommand(row: CommandCatalog.CommandRow): Decoders {
            val decoderMap = row.decoder ?: return fromDescription(row.description)
            return when {
                decoderMap.containsKey("temp") -> Temp
                decoderMap.containsKey("percent") -> Percent
                decoderMap.containsKey("percentCentered") -> Percent
                decoderMap.containsKey("rpm") -> Rpm
                decoderMap.containsKey("voltage") || decoderMap.containsKey("sensorVoltage") -> Voltage
                decoderMap.containsKey("speed") -> Speed
                decoderMap.containsKey("uas") -> {
                    val uas = decoderMap["uas"] as? Map<*, *>
                    val id = uas?.get("_0") as? Double
                    if (id == 30.0) Lambda else Voltage // Approximate
                }
                else -> fromDescription(row.description)
            }
        }

        private fun fromDescription(description: String): Decoders {
            val d = description.lowercase()
            return when {
                d.contains("temperature") -> Temp
                d.contains("rpm") -> Rpm
                d.contains("voltage") -> Voltage
                d.contains("speed") -> Speed
                d.contains("equivalence ratio") || d.contains("lambda") -> Lambda
                d.contains("percent") || d.contains("load") || d.contains("trim") || d.contains("level") -> Percent
                d.contains("trouble codes") -> Dtc
                d.contains("fuel system status") -> FuelStatus
                d.contains("monitor status") -> Status
                else -> None
            }
        }
    }
}

class TemperatureDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.isEmpty()) return DecodeResult.Failure("Insufficient data")
        val celsius = data[0] - 40.0
        return DecodeResult.Measurement(MeasurementResult(celsius, "°C"))
    }
}

class PercentDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.isEmpty()) return DecodeResult.Failure("Insufficient data")
        val pct = data[0] * 100.0 / 255.0
        return DecodeResult.Measurement(MeasurementResult(pct, "%"))
    }
}

class RpmDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 2) return DecodeResult.Failure("Insufficient data")
        val rpm = (data[0] * 256 + data[1]) / 4.0
        return DecodeResult.Measurement(MeasurementResult(rpm, "RPM"))
    }
}

class VoltageDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 2) return DecodeResult.Failure("Insufficient data")
        val volts = (data[0] * 256 + data[1]) / 1000.0
        return DecodeResult.Measurement(MeasurementResult(volts, "V"))
    }
}

class SpeedDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.isEmpty()) return DecodeResult.Failure("Insufficient data")
        val speed = data[0].toDouble()
        return DecodeResult.Measurement(MeasurementResult(speed, "km/h"))
    }
}

class LambdaDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 2) return DecodeResult.Failure("Insufficient data")
        val ratio = (data[0] * 256 + data[1]) / 32768.0
        return DecodeResult.Measurement(MeasurementResult(ratio, "lambda"))
    }
}

class DtcDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.isEmpty()) return DecodeResult.TroubleCodes(emptyList())
        val codes = mutableListOf<TroubleCodeMetadata>()
        for (i in 0 until data.size - 1 step 2) {
            val a = data[i]
            val b = data[i + 1]
            if (a == 0 && b == 0) continue
            val letter = when ((a and 0xC0) shr 6) {
                0 -> 'P'
                1 -> 'C'
                2 -> 'B'
                else -> 'U'
            }
            val d1 = (a and 0x30) shr 4
            val d2 = a and 0x0F
            val d3 = (b and 0xF0) shr 4
            val d4 = b and 0x0F
            val code = "$letter$d1${d2.toString(16)}${d3.toString(16)}${d4.toString(16)}".uppercase()
            val enriched = TroubleCodeCatalog.lookup(code)
            codes += enriched ?: TroubleCodeMetadata(code = code, severity = "Moderate")
        }
        return DecodeResult.TroubleCodes(codes)
    }
}

class FuelStatusDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 2) return DecodeResult.Failure("Insufficient data")
        val a = data[0]
        val b = data[1]
        fun decodeByte(v: Int): StatusCodeMetadata? = when {
            v and 0x01 != 0 -> StatusCodeMetadata("1", "Open loop due to insufficient engine temperature")
            v and 0x02 != 0 -> StatusCodeMetadata("2", "Closed loop, using oxygen sensor feedback")
            v and 0x04 != 0 -> StatusCodeMetadata("4", "Open loop due to engine load or fuel cut")
            v and 0x08 != 0 -> StatusCodeMetadata("8", "Open loop due to system failure")
            v and 0x10 != 0 -> StatusCodeMetadata("16", "Closed loop using at least one oxygen sensor")
            else -> null
        }
        return DecodeResult.FuelStatusResult(listOf(decodeByte(a), decodeByte(b)))
    }
}

class StatusDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 4) return DecodeResult.Failure("Insufficient data")
        val a = data[0] // milAndCount
        val b = data[1]
        val c = data[2]
        val d = data[3]
        val milOn = a and 0x80 != 0
        val dtcCount = a and 0x7F
        val monitors = listOf(
            ReadinessMonitor("Misfire", supported = true, ready = b and 0x10 == 0),
            ReadinessMonitor("Fuel System", supported = true, ready = b and 0x20 == 0),
            ReadinessMonitor("Comprehensive Components", supported = true, ready = b and 0x40 == 0),
            ReadinessMonitor("Catalyst", supported = c and 0x01 != 0, ready = d and 0x01 == 0),
            ReadinessMonitor("Heated Catalyst", supported = c and 0x02 != 0, ready = d and 0x02 == 0),
            ReadinessMonitor("Evaporative System", supported = c and 0x04 != 0, ready = d and 0x04 == 0),
            ReadinessMonitor("Secondary Air System", supported = c and 0x08 != 0, ready = d and 0x08 == 0),
            ReadinessMonitor("O2 Sensor", supported = c and 0x20 != 0, ready = d and 0x20 == 0),
            ReadinessMonitor("O2 Heater", supported = c and 0x40 != 0, ready = d and 0x40 == 0),
            ReadinessMonitor("EGR/VVT", supported = c and 0x80 != 0, ready = d and 0x80 == 0),
        )
        return DecodeResult.StatusResult(Status(milOn = milOn, dtcCount = dtcCount, monitors = monitors))
    }
}
