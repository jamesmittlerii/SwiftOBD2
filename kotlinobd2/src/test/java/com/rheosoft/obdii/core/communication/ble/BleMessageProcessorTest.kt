package com.rheosoft.obdii.core.communication.ble

import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class BleMessageProcessorTest {

    @Test
    fun completesOnElmPromptWithData() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("7E8 03 41 0F 2D\r\n>".toByteArray())
        assertEquals(listOf("7E8 03 41 0F 2D"), processor.awaitResponse(deferred, 1_000))
    }

    @Test
    fun completesWhenPromptArrivesInSecondChunk() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("7E803410F2D".toByteArray())
        val wait = async { processor.awaitResponse(deferred, 1_000) }
        processor.processReceivedData("\r\n>".toByteArray())
        assertEquals(listOf("7E803410F2D"), wait.await())
    }

    @Test
    fun completesOnElm327IdentityResponse() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("ELM327 v1.5\r\n>".toByteArray())
        assertEquals(listOf("ELM327 v1.5"), processor.awaitResponse(deferred, 1_000))
    }

    @Test
    fun completesOnOkResponse() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("OK\r\n>".toByteArray())
        assertEquals(listOf("OK"), processor.awaitResponse(deferred, 1_000))
    }

    @Test
    fun completesOnStoppedLineWithPrompt() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("STOPPED\r\n>".toByteArray())
        assertEquals(listOf("STOPPED"), processor.awaitResponse(deferred, 1_000))
    }

    @Test
    fun discardsOrphanPromptWithoutPendingCommand() = runTest {
        val processor = BleMessageProcessor()
        processor.processReceivedData(">\r\n".toByteArray())
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("OK\r\n>".toByteArray())
        assertEquals(listOf("OK"), processor.awaitResponse(deferred, 1_000))
    }

    @Test
    fun completesEmptyOnPromptOnlyResponse() = runTest {
        val processor = BleMessageProcessor()
        val deferred = processor.beginResponseWait()
        processor.processReceivedData("\r\n>".toByteArray())
        assertEquals(emptyList<String>(), processor.awaitResponse(deferred, 1_000))
    }
}
