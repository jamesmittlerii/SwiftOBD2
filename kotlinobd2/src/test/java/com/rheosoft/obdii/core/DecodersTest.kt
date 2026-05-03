package com.rheosoft.obdii.core

import org.junit.jupiter.api.Assertions.assertEquals
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
}
