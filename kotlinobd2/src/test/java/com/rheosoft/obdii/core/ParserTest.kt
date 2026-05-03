package com.rheosoft.obdii.core

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class ParserTest {

    @Test
    fun testSingleFrameInitialization() {
        val raw = listOf("7E8 06 41 00 BE 3F A8 13 00")
        val frames = Parser.parseFrames(raw)
        assertEquals(1, frames.size)
        assertEquals(FrameType.SingleFrame, frames[0].type)
        assertEquals(6, frames[0].dataLen)
    }

    @Test
    fun testCompactSingleFrameInitialization() {
        val raw = listOf("7E8064100BE3FA81300")
        val frames = Parser.parseFrames(raw)
        assertEquals(1, frames.size)
        assertEquals(FrameType.SingleFrame, frames[0].type)
        assertEquals(6, frames[0].dataLen)
        assertEquals(listOf(0x06, 0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13, 0x00), frames[0].data)
    }

    @Test
    fun testMultiFrameInitialization() {
        val raw = listOf("7E8 10 3E 00 00 00 00 00 00")
        val frames = Parser.parseFrames(raw)
        assertEquals(1, frames.size)
        assertEquals(FrameType.FirstFrame, frames[0].type)
        assertEquals(0x3E, frames[0].dataLen)
    }

    @Test
    fun testMessageInitialization() {
        val raw = listOf("7E8 06 41 00 BE 3F A8 13 00")
        val frames = Parser.parseFrames(raw)
        val messages = Parser.parseMessages(frames)
        assertEquals(1, messages.size)
        assertNotNull(messages[0].data)
        // TODO confirm what this should be
        //  assertEquals(listOf(0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13, 0x00), messages[0].data)
    }
    
    @Test
    fun testMultiFrameMessageAssembly() {
        val raw = listOf(
            "7E8 10 14 49 02 01 31 4E 34",
            "7E8 21 41 4C 33 41 50 37 44",
            "7E8 22 43 31 39 39 35 38 33"
        )
        val frames = Parser.parseFrames(raw)
        val messages = Parser.parseMessages(frames)
        assertEquals(1, messages.size)
        
        // Total data should be 0x14 (20) bytes.
        // First frame payload: 49 02 01 31 4E 34 (6 bytes)
        // Second frame payload: 41 4C 33 41 50 37 44 (7 bytes)
        // Third frame payload: 43 31 39 39 35 38 33 (7 bytes)
        // Total: 6+7+7 = 20 bytes.
        assertEquals(20, messages[0].data.size)
        assertEquals(0x49, messages[0].data[0])
        assertEquals(0x33, messages[0].data[19])
    }
}
