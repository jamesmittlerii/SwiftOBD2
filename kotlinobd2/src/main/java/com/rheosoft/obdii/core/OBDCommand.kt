package com.rheosoft.obdii.core

/**
 * Metadata and decoding logic for an OBD-II command.
 */
data class CommandProperties(
    val command: String,
    val description: String,
    val bytes: Int,
    val decoder: Decoders,
    val live: Boolean = false,
    val maxValue: Double = 100.0,
    val minValue: Double = 0.0,
) {
    fun decode(data: List<Int>, unit: MeasurementUnit = MeasurementUnit.Metric): DecodeResult {
        val decoderInstance = decoder.getDecoder() ?: return DecodeResult.Failure("No decoder found for $command")
        
        // Strip headers and protocol-specific bytes
        val serviceByte = when {
            command.startsWith("01") -> 0x41
            command.startsWith("03") -> 0x43
            command.startsWith("06") -> 0x46
            command.startsWith("09") -> 0x49
            command.startsWith("22") -> 0x62
            else -> -1
        }
        
        val payload = if (serviceByte != -1) {
            val idx = data.indexOf(serviceByte)
            if (idx >= 0) {
                // For Mode 1/6/9/22, we skip Service (1 byte) + PID/TID/etc (1 or 2 bytes)
                // For Mode 3, we skip Service (1 byte) + Count (1 byte)
                if (serviceByte == 0x43 || serviceByte == 0x41) {
                    data.drop(idx + 2) 
                } else {
                    data.drop(idx + 1)
                }
            } else data
        } else data
        
        return decoderInstance.decode(payload, unit)
    }
}

/**
 * Represents the standard modes and custom modes of OBD-II commands.
 */
sealed class OBDCommand {
    abstract val properties: CommandProperties

    data class Mode1(val pid: String) : OBDCommand() {
        override val properties: CommandProperties by lazy {
            CommandCatalog.allCommands["01$pid"]?.toCommandProperties()
                ?: CommandProperties("01$pid", "Unknown Mode 1 PID", 0, Decoders.None)
        }
    }

    data class Mode3(val dummy: String = "") : OBDCommand() {
        override val properties = CommandProperties("03", "Read DTCs", 0, Decoders.Dtc)
    }
}

private fun CommandCatalog.CommandRow.toCommandProperties(): CommandProperties {
    return CommandProperties(
        command = this.command,
        description = this.description,
        bytes = this.bytes,
        decoder = Decoders.fromCommand(this),
        live = this.live,
        maxValue = this.maxValue,
        minValue = this.minValue
    )
}
