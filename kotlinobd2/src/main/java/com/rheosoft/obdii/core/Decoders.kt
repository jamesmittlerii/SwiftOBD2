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
                decoderMap.containsKey("dtc") -> Dtc
                decoderMap.containsKey("fuelStatus") -> FuelStatus
                decoderMap.containsKey("status") -> Status
                decoderMap.containsKey("uas") -> None
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

private data class UasSpec(
    val signed: Boolean,
    val scale: Double,
    val unit: String,
    val offset: Double = 0.0,
)

private val uasSpecs: Map<Int, UasSpec> = mapOf(
    0x01 to UasSpec(false, 1.0, "count"),
    0x02 to UasSpec(false, 0.1, "count"),
    0x03 to UasSpec(false, 0.01, "count"),
    0x04 to UasSpec(false, 0.001, "count"),
    0x05 to UasSpec(false, 0.0000305, "count"),
    0x06 to UasSpec(false, 0.000305, "count"),
    0x07 to UasSpec(false, 0.25, "RPM"),
    0x09 to UasSpec(false, 1.0, "km/h"),
    0x0A to UasSpec(false, 0.122, "mV"),
    0x0B to UasSpec(false, 0.001, "V"),
    0x10 to UasSpec(false, 1.0, "ms"),
    0x11 to UasSpec(false, 100.0, "ms"),
    0x12 to UasSpec(false, 1.0, "s"),
    0x13 to UasSpec(false, 1.0, "microohms"),
    0x14 to UasSpec(false, 1.0, "ohms"),
    0x15 to UasSpec(false, 1.0, "kiloohms"),
    0x16 to UasSpec(false, 0.1, "°C", -40.0),
    0x17 to UasSpec(false, 0.01, "kPa"),
    0x18 to UasSpec(false, 0.0117, "kPa"),
    0x19 to UasSpec(false, 0.079, "kPa"),
    0x1A to UasSpec(false, 1.0, "kPa"),
    0x1B to UasSpec(false, 10.0, "kPa"),
    0x1C to UasSpec(false, 0.01, "°"),
    0x1D to UasSpec(false, 0.5, "°"),
    0x1E to UasSpec(false, 0.0000305, "lambda"),
    0x1F to UasSpec(false, 0.05, "lambda"),
    0x20 to UasSpec(false, 0.00390625, "lambda"),
    0x21 to UasSpec(false, 1.0, "mHz"),
    0x22 to UasSpec(false, 1.0, "Hz"),
    0x23 to UasSpec(false, 1.0, "kHz"),
    0x24 to UasSpec(false, 1.0, "count"),
    0x25 to UasSpec(false, 1.0, "km"),
    0x27 to UasSpec(false, 0.01, "g/s"),
    0x81 to UasSpec(true, 1.0, "count"),
    0x82 to UasSpec(true, 0.1, "count"),
    0x83 to UasSpec(true, 0.01, "count"),
    0x84 to UasSpec(true, 0.001, "count"),
    0x85 to UasSpec(true, 0.0000305, "count"),
    0x86 to UasSpec(true, 0.000305, "count"),
    0x87 to UasSpec(true, 1.0, "ppm"),
    0x8A to UasSpec(true, 0.122, "mV"),
    0x8B to UasSpec(true, 0.001, "V"),
    0x8C to UasSpec(true, 0.01, "V"),
    0x8D to UasSpec(true, 0.00390625, "mA"),
    0x8E to UasSpec(true, 0.001, "A"),
    0x90 to UasSpec(true, 1.0, "ms"),
    0x96 to UasSpec(true, 0.1, "°C"),
    0x99 to UasSpec(true, 0.1, "kPa"),
    0xFC to UasSpec(true, 0.01, "kPa"),
    0xFD to UasSpec(true, 0.001, "kPa"),
    0xFE to UasSpec(true, 0.25, "Pa"),
)

class UasDecoder(private val id: Int) : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        val spec = uasSpecs[id] ?: return DecodeResult.Failure("Unsupported UAS id: $id")
        if (data.isEmpty()) return DecodeResult.Failure("Insufficient data")

        val bitWidth = data.size * 8
        var intValue = data.fold(0L) { acc, byte -> (acc shl 8) or (byte and 0xFF).toLong() }
        if (spec.signed) {
            val signBit = 1L shl (bitWidth - 1)
            if (intValue and signBit != 0L) {
                intValue -= 1L shl bitWidth
            }
        }

        val baseValue = intValue.toDouble() * spec.scale + spec.offset
        
        if (unit == MeasurementUnit.Imperial) {
            val (convValue, convUnit) = convertToImperial(baseValue, spec.unit)
            return DecodeResult.Measurement(MeasurementResult(convValue, convUnit))
        }

        return DecodeResult.Measurement(
            MeasurementResult(
                value = baseValue,
                unit = spec.unit,
            ),
        )
    }

    private fun convertToImperial(value: Double, baseUnit: String): Pair<Double, String> {
        return when (baseUnit) {
            "°C" -> (value * 9.0 / 5.0 + 32.0) to "°F"
            "km" -> (value * 0.621371) to "mi"
            "km/h" -> (value * 0.621371) to "mph"
            "kPa" -> (value * 0.145038) to "psi"
            "g/s" -> (value * 0.132277) to "lb/min"
            "L/h" -> (value * 0.264172) to "gal/h"
            else -> value to baseUnit
        }
    }
}

class TemperatureDecoder : Decoder {
    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.isEmpty()) return DecodeResult.Failure("Insufficient data")
        val celsius = data[0] - 40.0
        return if (unit == MeasurementUnit.Imperial) {
            DecodeResult.Measurement(MeasurementResult((celsius * 9.0 / 5.0) + 32.0, "°F"))
        } else {
            DecodeResult.Measurement(MeasurementResult(celsius, "°C"))
        }
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
        val kmh = data[0].toDouble()
        return if (unit == MeasurementUnit.Imperial) {
            DecodeResult.Measurement(MeasurementResult(kmh * 0.621371, "mph"))
        } else {
            DecodeResult.Measurement(MeasurementResult(kmh, "km/h"))
        }
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
            codes += enriched ?: TroubleCodeMetadata(code = code, severity = TroubleCodeCatalog.severityFor(code))
        }
        return DecodeResult.TroubleCodes(codes)
    }
}

class FuelStatusDecoder : Decoder {
    private val fuelStatus = mapOf(
        "0" to "Unavailable",
        "1" to "Open Loop (cold engine)",
        "2" to "Closed Loop (normal operation)",
        "3" to "Open Loop (load/fuel cut)",
        "4" to "Open loop: system fault detected",
        "5" to "Closed loop: O₂ fault in feedback",
    )

    override fun decode(data: List<Int>, unit: MeasurementUnit): DecodeResult {
        if (data.size < 2) return DecodeResult.Failure("Insufficient data")
        val a = data[0]
        val b = data[1]
        return DecodeResult.FuelStatusResult(listOf(decodeByte(a), decodeByte(b)))
    }

    private fun decodeByte(v: Int): StatusCodeMetadata? {
        if (v == 0) return StatusCodeMetadata("0", fuelStatus["0"]!!)
        // Find the single set bit; code = 8 - bitIndex (matching Swift: 8 - bits.firstIndex(of: 1))
        for (i in 0..7) {
            if ((v shr (7 - i)) and 1 == 1) {
                val code = (8 - i).toString()
                val description = fuelStatus[code] ?: return null
                return StatusCodeMetadata(code, description)
            }
        }
        return null
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
        val isDiesel = b and 0x08 != 0
        val monitors = if (isDiesel) {
            listOf(
                ReadinessMonitor("Misfire", supported = true, ready = b and 0x10 == 0),
                ReadinessMonitor("Fuel System", supported = true, ready = b and 0x20 == 0),
                ReadinessMonitor("Comprehensive Components", supported = true, ready = b and 0x40 == 0),
                ReadinessMonitor("NMHC catalyst", supported = c and 0x01 != 0, ready = d and 0x01 == 0),
                ReadinessMonitor("HNOx/SCR Catalyst", supported = c and 0x02 != 0, ready = d and 0x02 == 0),
                ReadinessMonitor("Boost pressure", supported = c and 0x08 != 0, ready = d and 0x08 == 0),
                ReadinessMonitor("Exhaust gas", supported = c and 0x20 != 0, ready = d and 0x20 == 0),
                ReadinessMonitor("PM filter", supported = c and 0x40 != 0, ready = d and 0x40 == 0),
                ReadinessMonitor("EGR/VVT System", supported = c and 0x80 != 0, ready = d and 0x80 == 0),
            )
        } else {
            listOf(
                ReadinessMonitor("Misfire", supported = true, ready = b and 0x10 == 0),
                ReadinessMonitor("Fuel System", supported = true, ready = b and 0x20 == 0),
                ReadinessMonitor("Comprehensive Components", supported = true, ready = b and 0x40 == 0),
                ReadinessMonitor("Catalyst", supported = c and 0x01 != 0, ready = d and 0x01 == 0),
                ReadinessMonitor("Heated Catalyst", supported = c and 0x02 != 0, ready = d and 0x02 == 0),
                ReadinessMonitor("Evaporative System", supported = c and 0x04 != 0, ready = d and 0x04 == 0),
                ReadinessMonitor("Secondary Air System", supported = c and 0x08 != 0, ready = d and 0x08 == 0),
                ReadinessMonitor("O₂ Sensor", supported = c and 0x20 != 0, ready = d and 0x20 == 0),
                ReadinessMonitor("O₂ Heater", supported = c and 0x40 != 0, ready = d and 0x40 == 0),
                ReadinessMonitor("EGR/VVT System", supported = c and 0x80 != 0, ready = d and 0x80 == 0),
            )
        }
        return DecodeResult.StatusResult(Status(milOn = milOn, dtcCount = dtcCount, monitors = monitors))
    }
}
