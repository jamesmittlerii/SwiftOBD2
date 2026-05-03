package com.rheosoft.obdii.core

data class Frame(
    val raw: String,
    val data: List<Int>,
    val type: FrameType,
    val dataLen: Int? = null,
    val seqIndex: Int = 0
)

data class Message(
    val frames: List<Frame>,
    val data: List<Int>
)

object Parser {
    fun parseFrames(lines: List<String>): List<Frame> {
        val frames = mutableListOf<Frame>()
        for (line in lines) {
            val trimmed = line.trim().uppercase()
            if (trimmed.isEmpty() || trimmed.contains("SEARCHING") || trimmed.contains("NO DATA") || trimmed.contains("OK") || trimmed.contains("ELM")) {
                continue
            }

            val tokens = tokenizeResponseLine(trimmed)
            val bytes = mutableListOf<Int>()
            var header = ""
            
            var startIdx = 0
            if (tokens.isNotEmpty() && tokens[0].length == 3) {
                header = tokens[0]
                startIdx = 1
            } else if (tokens.size >= 3 && tokens[0].length == 2 && tokens[1].length == 2 && tokens[2].length == 2) {
                // Legacy 3-byte header
                header = tokens.take(3).joinToString("")
                startIdx = 3
            }
            
            for (i in startIdx until tokens.size) {
                tokens[i].toIntOrNull(16)?.let(bytes::add)
            }
            
            if (bytes.isEmpty()) continue
            
            // Check for CAN vs Legacy
            val typeByte = bytes[0]
            val type = FrameType.fromInt(typeByte) 
            
            if (type != null && header.length == 3) {
                // CAN Frame
                if (bytes.size < 6 || bytes.size > 12) {
                    obdError("Invalid frame size: ${bytes.size} bytes", LogCategory.Parsing)
                }

                val dataLen = when (type) {
                    FrameType.SingleFrame -> typeByte and 0x0F
                    FrameType.FirstFrame -> ((typeByte and 0x0F) shl 8) or bytes[1]
                    else -> null
                }
                val seqIndex = if (type == FrameType.ConsecutiveFrame) typeByte and 0x0F else 0
                frames.add(Frame(canonicalRaw(header, bytes), bytes, type, dataLen, seqIndex))
            } else {
                if (header.length == 3 && type == null) {
                    obdError("Invalid frame type detected", LogCategory.Parsing)
                }
                // Legacy Frame (No PCI, just Mode + Data + Checksum)
                // Swift LegacyParcer: dropFirst(3).dropLast()
                // Our bytes already dropped the 3-byte header.
                // We just need to drop the checksum (last byte).
                if (bytes.size >= 2) {
                    val legacyData = bytes.dropLast(1)
                    // We'll treat it as a SingleFrame for simplicity in the assembler
                    frames.add(Frame(trimmed, legacyData, FrameType.SingleFrame, legacyData.size, 0))
                }
            }
        }
        return frames
    }

    private fun tokenizeResponseLine(line: String): List<String> {
        val spaced = line.split(Regex("\\s+")).filter { it.isNotBlank() }
        if (spaced.size > 1) return spaced

        val compact = line.replace(" ", "")
        if (compact.length < 2 || !compact.all { it in '0'..'9' || it in 'A'..'F' }) {
            return spaced
        }

        val hasCanHeader = compact.length >= 5 && (compact.length - 3) % 2 == 0
        val start = if (hasCanHeader) 3 else 0
        if (!hasCanHeader && compact.length % 2 != 0) return spaced
        val tokens = mutableListOf<String>()
        if (hasCanHeader) tokens += compact.take(3)
        for (i in start until compact.length step 2) {
            tokens += compact.substring(i, i + 2)
        }
        return tokens
    }

    private fun canonicalRaw(header: String, bytes: List<Int>): String =
        "$header ${bytes.joinToString(" ") { "%02X".format(it) }}"

    fun parseMessages(frames: List<Frame>): List<Message> {
        if (frames.isEmpty()) return emptyList()
        
        val messages = mutableListOf<Message>()
        
        // Group by CAN ID or similar? For now, we process all frames.
        
        // Single frames (includes our simplified legacy frames)
        val singleFrames = frames.filter { it.type == FrameType.SingleFrame }
        for (f in singleFrames) {
            // CAN SingleFrame: PCI (1 byte) + Mode (1 byte)
            // Legacy Frame: Mode (1 byte)
            // We distinguish them by whether a CAN header (3 chars) was used.
            // For now, let's look at data length and content.
            
            val isCan = f.raw.startsWith("7E8") || f.raw.startsWith("7E9") // Simplified
            val dropCount = if (isCan) 2 else 1
            
            if (f.data.size >= dropCount) {
                messages.add(Message(listOf(f), f.data.drop(dropCount)))
            }
        }
        
        // Multi-frame messages
        val firstFrames = frames.filter { it.type == FrameType.FirstFrame }
        for (ff in firstFrames) {
            val consecutive = frames.filter { it.type == FrameType.ConsecutiveFrame }
            // In a real app we'd match CAN ID and handle interleaving
            val assembledData = mutableListOf<Int>()
            assembledData.addAll(ff.data.drop(2)) // Drop FF PCI (2 bytes)
            for (cf in consecutive) {
                assembledData.addAll(cf.data.drop(1)) // Drop CF PCI (1 byte)
            }
            
            // Limit to expected data length
            val finalData = if (ff.dataLen != null && ff.dataLen < assembledData.size) {
                assembledData.take(ff.dataLen)
            } else assembledData
            
            messages.add(Message(listOf(ff) + consecutive, finalData))
        }
        
        return messages
    }

    fun parseHexBytes(lines: List<String>): List<Int> {
        val frames = parseFrames(lines)
        val messages = parseMessages(frames)
        return messages.firstOrNull()?.data ?: emptyList()
    }
}
