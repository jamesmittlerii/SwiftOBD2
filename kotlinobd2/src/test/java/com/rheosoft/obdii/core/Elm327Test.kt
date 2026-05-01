package com.rheosoft.obdii.core

import com.rheosoft.obdii.core.communication.MockComm
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class Elm327Test {

    @Test
    fun testAdapterInitialization() = runBlocking {
        val comm = MockComm()
        val sut = Elm327(comm)
        
        // This just executes the sequence of AT commands
        // In MockComm, most AT commands return OK
        sut.adapterInitialization()
        
        // We can verify that it sends the commands if we add a history to MockComm
        // For now, just ensuring it doesn't crash
    }

    @Test
    fun testSendCommand() = runBlocking {
        val comm = MockComm()
        val sut = Elm327(comm)
        
        val response = sut.sendCommand("010C")
        // MockComm for 010C returns 41 0C ...
        assertEquals(true, response.any { it.contains("41 0C") })
    }
}
