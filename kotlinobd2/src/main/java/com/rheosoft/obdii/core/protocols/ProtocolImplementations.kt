package com.rheosoft.obdii.core.protocols

import com.rheosoft.obdii.core.ECUID
import com.rheosoft.obdii.core.Message
import com.rheosoft.obdii.core.Parser

interface CANProtocol {
    val elmID: String
    val name: String
    fun parse(lines: List<String>): List<Message>
}

abstract class BaseCANProtocol : CANProtocol {
    protected fun parseDefault(lines: List<String>, idBits: Int): List<Message> {
        val frames = Parser.parseFrames(lines)
        return Parser.parseMessages(frames)
    }
}

class ISO_15765_4_11bit_500k : BaseCANProtocol() {
    override val elmID = "6"
    override val name = "ISO 15765-4 (CAN 11/500)"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class ISO_15765_4_29bit_500k : BaseCANProtocol() {
    override val elmID = "7"
    override val name = "ISO 15765-4 (CAN 29/500)"
    override fun parse(lines: List<String>) = parseDefault(lines, 29)
}

class ISO_15765_4_11bit_250K : BaseCANProtocol() {
    override val elmID = "8"
    override val name = "ISO 15765-4 (CAN 11/250)"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class ISO_15765_4_29bit_250k : BaseCANProtocol() {
    override val elmID = "9"
    override val name = "ISO 15765-4 (CAN 29/250)"
    override fun parse(lines: List<String>) = parseDefault(lines, 29)
}

// Legacy Protocols (Mocked for now as Parser handles mostly CAN)
class SAE_J1850_PWM : BaseCANProtocol() {
    override val elmID = "1"
    override val name = "SAE J1850 PWM"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class SAE_J1850_VPW : BaseCANProtocol() {
    override val elmID = "2"
    override val name = "SAE J1850 VPW"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class ISO_9141_2 : BaseCANProtocol() {
    override val elmID = "3"
    override val name = "ISO 9141-2"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class ISO_14230_4_KWP_5Baud : BaseCANProtocol() {
    override val elmID = "4"
    override val name = "ISO 14230-4 KWP (5 baud init)"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}

class ISO_14230_4_KWP_Fast : BaseCANProtocol() {
    override val elmID = "5"
    override val name = "ISO 14230-4 KWP (fast init)"
    override fun parse(lines: List<String>) = parseDefault(lines, 11)
}
