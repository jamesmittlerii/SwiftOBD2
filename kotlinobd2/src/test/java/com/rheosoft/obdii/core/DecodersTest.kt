package com.rheosoft.obdii.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test
import kotlin.test.assertTrue

class DecodersTest {

    @Test
    fun testPercent() {
        val tests = mapOf(
            listOf(0x00) to 0.0,
            listOf(0xFF) to 100.0
        )
        for ((data, expected) in tests) {
            val result = PercentDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 1.0)
            assertEquals("%", result.value.unit)
        }
    }

    @Test
    fun testTemp() {
        val tests = mapOf(
            listOf(0x00) to -40.0,
            listOf(0xFF) to 215.0
        )
        for ((data, expected) in tests) {
            val result = TemperatureDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 0.01)
            assertEquals("°C", result.value.unit)
        }
    }

    @Test
    fun testRpm() {
        val tests = mapOf(
            listOf(0x00, 0x00) to 0.0,
            listOf(0x10, 0x00) to 1024.0 // (16*256 + 0) / 4 = 4096 / 4 = 1024
        )
        for ((data, expected) in tests) {
            val result = RpmDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 0.01)
        }
    }

    @Test
    fun testVoltage() {
        val tests = mapOf(
            listOf(0x00, 0x00) to 0.0,
            listOf(0x35, 0x20) to 13.6 // (53*256 + 32) / 1000 = (13568 + 32) / 1000 = 13.6
        )
        for ((data, expected) in tests) {
            val result = VoltageDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 0.01)
        }
    }

    @Test
    fun testSpeed() {
        val tests = mapOf(
            listOf(0x00) to 0.0,
            listOf(0x64) to 100.0
        )
        for ((data, expected) in tests) {
            val result = SpeedDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 0.01)
        }
    }

    @Test
    fun testLambda() {
        val tests = mapOf(
            listOf(0x00, 0x00) to 0.0,
            listOf(0x80, 0x00) to 1.0 // (128*256 + 0) / 32768 = 32768 / 32768 = 1.0
        )
        for ((data, expected) in tests) {
            val result = LambdaDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected, result.value.value, 0.001)
        }
    }

    @Test
    fun testDtc() {
        val tests = mapOf(
            listOf(0x01, 0x04) to listOf("P0104"),
            listOf(0x01, 0x04, 0x80, 0x03, 0x41, 0x23) to listOf("P0104", "B0003", "C0123")
        )
        for ((data, expected) in tests) {
            val result = DtcDecoder().decode(data, MeasurementUnit.Metric)
            assertTrue(result is DecodeResult.TroubleCodes)
            val codes = result.codes.map { it.code }
            assertEquals(expected, codes)
        }
    }

    @Test
    fun testCatalogStatusDecoderKey() {
        val result = OBDCommand.Mode1("01").properties.decode(listOf(0x41, 0x01, 0x87, 0x70, 0xEF, 0xEF))

        assertTrue(result is DecodeResult.StatusResult)
        assertEquals(true, result.value.milOn)
        assertEquals(7, result.value.dtcCount)
        assertTrue(result.value.monitors.isNotEmpty())
    }

    @Test
    fun testMode1RpmDecodeAcceptsServiceStrippedPayload() {
        val result = OBDCommand.Mode1("0C").properties.decode(listOf(0x0C, 0x2D, 0xD3))

        assertTrue(result is DecodeResult.Measurement)
        assertEquals(2932.75, result.value.value, 0.01)
        assertEquals("RPM", result.value.unit)
    }

    @Test
    fun testMode1SpeedUsesUasSpeedDecoder() {
        val result = OBDCommand.Mode1("0D").properties.decode(listOf(0x41, 0x0D, 0x2D))

        assertTrue(result is DecodeResult.Measurement)
        assertEquals(45.0, result.value.value, 0.01)
        assertEquals("km/h", result.value.unit)
    }

    @Test
    fun measurementUnitNextTogglesBetweenMetricAndImperial() {
        assertEquals(MeasurementUnit.Imperial, MeasurementUnit.Metric.next)
        assertEquals(MeasurementUnit.Metric, MeasurementUnit.Imperial.next)
    }

    @Test
    fun decoderFactoryReturnsExpectedImplementations() {
        val expectedTypes = mapOf(
            Decoders.Temp to TemperatureDecoder::class,
            Decoders.Percent to PercentDecoder::class,
            Decoders.Rpm to RpmDecoder::class,
            Decoders.Voltage to VoltageDecoder::class,
            Decoders.Speed to SpeedDecoder::class,
            Decoders.Dtc to DtcDecoder::class,
            Decoders.FuelStatus to FuelStatusDecoder::class,
            Decoders.Status to StatusDecoder::class,
            Decoders.Lambda to LambdaDecoder::class,
        )

        expectedTypes.forEach { (decoder, expectedType) ->
            assertEquals(expectedType, decoder.getDecoder()!!::class)
        }
        assertNull(Decoders.None.getDecoder())
    }

    @Test
    fun decoderSelectionUsesExplicitDecoderMaps() {
        val cases = listOf(
            mapOf("temp" to true) to Decoders.Temp,
            mapOf("percent" to true) to Decoders.Percent,
            mapOf("percentCentered" to true) to Decoders.Percent,
            mapOf("rpm" to true) to Decoders.Rpm,
            mapOf("voltage" to true) to Decoders.Voltage,
            mapOf("sensorVoltage" to true) to Decoders.Voltage,
            mapOf("speed" to true) to Decoders.Speed,
            mapOf("dtc" to true) to Decoders.Dtc,
            mapOf("fuelStatus" to true) to Decoders.FuelStatus,
            mapOf("status" to true) to Decoders.Status,
            mapOf("uas" to true) to Decoders.None,
            mapOf("unknown" to true) to Decoders.Lambda,
        )

        cases.forEach { (decoderMap, expected) ->
            val row = CommandCatalog.CommandRow(
                command = "0100",
                description = "Equivalence ratio",
                bytes = 1,
                decoder = decoderMap,
            )
            assertEquals(expected, Decoders.fromCommand(row))
        }
    }

    @Test
    fun decoderSelectionFallsBackToDescriptions() {
        val cases = mapOf(
            "engine temperature" to Decoders.Temp,
            "engine rpm" to Decoders.Rpm,
            "control module voltage" to Decoders.Voltage,
            "vehicle speed" to Decoders.Speed,
            "lambda sensor" to Decoders.Lambda,
            "equivalence ratio" to Decoders.Lambda,
            "calculated load" to Decoders.Percent,
            "fuel trim" to Decoders.Percent,
            "fuel level" to Decoders.Percent,
            "stored trouble codes" to Decoders.Dtc,
            "fuel system status" to Decoders.FuelStatus,
            "monitor status this cycle" to Decoders.Status,
            "plain text response" to Decoders.None,
        )

        cases.forEach { (description, expected) ->
            val row = CommandCatalog.CommandRow(command = "0100", description = description, bytes = 1)
            assertEquals(expected, Decoders.fromCommand(row))
        }
    }

    @Test
    fun decodersReportInsufficientData() {
        val failures = listOf(
            TemperatureDecoder().decode(emptyList(), MeasurementUnit.Metric),
            PercentDecoder().decode(emptyList(), MeasurementUnit.Metric),
            RpmDecoder().decode(listOf(0x12), MeasurementUnit.Metric),
            VoltageDecoder().decode(listOf(0x12), MeasurementUnit.Metric),
            SpeedDecoder().decode(emptyList(), MeasurementUnit.Metric),
            LambdaDecoder().decode(listOf(0x12), MeasurementUnit.Metric),
            FuelStatusDecoder().decode(listOf(0x01), MeasurementUnit.Metric),
            StatusDecoder().decode(listOf(0x00, 0x00, 0x00), MeasurementUnit.Metric),
            UasDecoder(0x01).decode(emptyList(), MeasurementUnit.Metric),
        )

        failures.forEach { result ->
            assertTrue(result is DecodeResult.Failure)
            assertEquals("Insufficient data", result.message)
        }
    }

    @Test
    fun simpleDecodersSupportImperialUnits() {
        val temp = TemperatureDecoder().decode(listOf(0x50), MeasurementUnit.Imperial)
        assertTrue(temp is DecodeResult.Measurement)
        assertEquals(104.0, temp.value.value, 0.01)
        assertEquals("°F", temp.value.unit)

        val speed = SpeedDecoder().decode(listOf(100), MeasurementUnit.Imperial)
        assertTrue(speed is DecodeResult.Measurement)
        assertEquals(62.1371, speed.value.value, 0.0001)
        assertEquals("mph", speed.value.unit)
    }

    @Test
    fun uasDecoderCoversSignedValuesUnsupportedIdsAndImperialConversions() {
        val unsupported = UasDecoder(0xFF).decode(listOf(0x01), MeasurementUnit.Metric)
        assertTrue(unsupported is DecodeResult.Failure)
        assertEquals("Unsupported UAS id: 255", unsupported.message)

        val signedNegative = UasDecoder(0x81).decode(listOf(0xFF), MeasurementUnit.Metric)
        assertTrue(signedNegative is DecodeResult.Measurement)
        assertEquals(-1.0, signedNegative.value.value, 0.01)
        assertEquals("count", signedNegative.value.unit)

        val signedPositive = UasDecoder(0x81).decode(listOf(0x01), MeasurementUnit.Metric)
        assertTrue(signedPositive is DecodeResult.Measurement)
        assertEquals(1.0, signedPositive.value.value, 0.01)

        val conversions = listOf(
            Triple(UasDecoder(0x16), listOf(0x03, 0x20), MeasurementResult(104.0, "°F")),
            Triple(UasDecoder(0x25), listOf(100), MeasurementResult(62.1371, "mi")),
            Triple(UasDecoder(0x09), listOf(100), MeasurementResult(62.1371, "mph")),
            Triple(UasDecoder(0x1A), listOf(100), MeasurementResult(14.5038, "psi")),
            Triple(UasDecoder(0x27), listOf(100), MeasurementResult(0.132277, "lb/min")),
            Triple(UasDecoder(0x01), listOf(100), MeasurementResult(100.0, "count")),
        )

        conversions.forEach { (decoder, data, expected) ->
            val result = decoder.decode(data, MeasurementUnit.Imperial)
            assertTrue(result is DecodeResult.Measurement)
            assertEquals(expected.value, result.value.value, 0.0001)
            assertEquals(expected.unit, result.value.unit)
        }
    }

    @Test
    fun dtcDecoderHandlesEmptyZeroPaddingFallbackAndAllCodeFamilies() {
        val empty = DtcDecoder().decode(emptyList(), MeasurementUnit.Metric)
        assertTrue(empty is DecodeResult.TroubleCodes)
        assertEquals(emptyList<String>(), empty.codes.map { it.code })

        val result = DtcDecoder().decode(
            listOf(0x00, 0x00, 0x01, 0x04, 0x40, 0x23, 0x80, 0x03, 0xC0, 0x00),
            MeasurementUnit.Metric,
        )

        assertTrue(result is DecodeResult.TroubleCodes)
        assertEquals(listOf("P0104", "C0023", "B0003", "U0000"), result.codes.map { it.code })
    }

    @Test
    fun fuelStatusDecoderHandlesUnavailableKnownAndUnknownBitCodes() {
        val result = FuelStatusDecoder().decode(listOf(0x00, 0x08), MeasurementUnit.Metric)
        assertTrue(result is DecodeResult.FuelStatusResult)
        assertEquals("0", result.status[0]?.code)
        assertEquals("Unavailable", result.status[0]?.description)
        assertEquals("4", result.status[1]?.code)
        assertEquals("Open loop: system fault detected", result.status[1]?.description)

        val unknown = FuelStatusDecoder().decode(listOf(0x80, 0x20), MeasurementUnit.Metric)
        assertTrue(unknown is DecodeResult.FuelStatusResult)
        assertNull(unknown.status[0])
        assertNull(unknown.status[1])
    }

    @Test
    fun statusDecoderCoversDieselAndGasolineReadinessBranches() {
        val diesel = StatusDecoder().decode(listOf(0x02, 0x78, 0xCB, 0x49), MeasurementUnit.Metric)
        assertTrue(diesel is DecodeResult.StatusResult)
        assertEquals(false, diesel.value.milOn)
        assertEquals(2, diesel.value.dtcCount)
        assertEquals("NMHC catalyst", diesel.value.monitors[3].name)
        assertEquals(true, diesel.value.monitors[3].supported)
        assertEquals(false, diesel.value.monitors[3].ready)

        val gasoline = StatusDecoder().decode(listOf(0x87, 0x70, 0xEF, 0x00), MeasurementUnit.Metric)
        assertTrue(gasoline is DecodeResult.StatusResult)
        assertEquals(true, gasoline.value.milOn)
        assertEquals(7, gasoline.value.dtcCount)
        assertEquals("Catalyst", gasoline.value.monitors[3].name)
        assertEquals(true, gasoline.value.monitors[3].supported)
        assertEquals(true, gasoline.value.monitors[3].ready)
    }
}
