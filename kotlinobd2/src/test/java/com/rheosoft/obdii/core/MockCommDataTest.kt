package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test
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
    fun testObdConnectionLibraryParsing() = runBlocking {
        ObdConnectionLibrary.resetForTests()
        ObdConnectionLibrary.initialize()
        
        val testPids = setOf("0105", "010F", "0142", "0144")
        ObdConnectionLibrary.setInterestedPids(testPids)
        
        ObdConnectionLibrary.connect()
        
        // Wait for polling
        var found = false
        for (i in 0 until 30) {
            if (ObdConnectionLibrary.pidStats.isNotEmpty()) {
                found = true
                break
            }
            delay(200)
        }
        
        val stats = ObdConnectionLibrary.pidStats
        assertTrue(found, "Should have collected some stats. Stats: ${stats.keys}")
        assertTrue(stats.containsKey("0105"), "Should have stats for 0105. Stats: ${stats.keys}")
        
        ObdConnectionLibrary.disconnect()
    }
}
