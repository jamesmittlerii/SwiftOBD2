package com.rheosoft.obdii.core

enum class FrameType(val value: Int) {
    SingleFrame(0x00),
    FirstFrame(0x10),
    ConsecutiveFrame(0x20),
    FlowControl(0x30);

    companion object {
        fun fromInt(v: Int): FrameType? = entries.find { it.value == (v and 0xF0) }
    }
}

enum class ECUID(val value: Int) {
    Engine(0),
    Transmission(1),
    Unknown(-1);

    companion object {
        fun fromInt(v: Int): ECUID = entries.find { it.value == v } ?: Unknown
    }
}
