package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class MockCommDataTest {

    @Test
    fun testMockRawResponses() = runBlocking {
        val mock = MockComm()
        val response = mock.sendCommand("0105")
        val responseString = response.joinToString(" ")
        assertTrue(responseString.contains("41 05"), "Response should contain 41 05. Got: $responseString")
    }

    @Test
    fun testObdServiceDecodesMockResponse() = runBlocking {
        val service = ObdService(LibraryConnectionType.demo)

        service.startConnection()
        val response = service.sendCommand("0105")
        val bytes = Parser.parseHexBytes(response)
        val result = OBDCommand.Mode1("05").properties.decode(bytes)

        assertTrue(bytes.isNotEmpty(), "Should parse response bytes from mock service")
        assertTrue(result is DecodeResult.Measurement, "Should decode coolant temperature. Result: $result")
        assertNotNull(result.value)

        service.stopConnection()
    }
}
