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
            if (shouldSkipLine(trimmed)) continue

            val tokens = tokenizeResponseLine(trimmed)
            val parsed = parseHeaderAndBytes(tokens)
            val bytes = parsed.bytes
            
            if (bytes.isEmpty()) continue
            
            val typeByte = bytes[0]
            val type = FrameType.fromInt(typeByte) 
            
            if (type != null && parsed.hasCanHeader) {
                frames.add(canFrame(parsed.header, bytes, type, typeByte))
            } else {
                legacyFrame(trimmed, bytes, parsed.hasCanHeader, type)?.let(frames::add)
            }
        }
        return frames
    }

    private data class ParsedLine(val header: String, val bytes: List<Int>) {
        val hasCanHeader: Boolean = header.length == 3
    }

    private fun shouldSkipLine(line: String): Boolean =
        line.isEmpty() ||
            line.contains("SEARCHING") ||
            line.contains("NO DATA") ||
            line.contains("OK") ||
            line.contains("ELM")

    private fun parseHeaderAndBytes(tokens: List<String>): ParsedLine {
        val headerSize = when {
            tokens.isNotEmpty() && tokens[0].length == 3 -> 1
            tokens.size >= 3 && tokens.take(3).all { it.length == 2 } -> 3
            else -> 0
        }
        val header = when (headerSize) {
            1 -> tokens[0]
            3 -> tokens.take(3).joinToString("")
            else -> ""
        }
        val bytes = tokens
            .drop(headerSize)
            .mapNotNull { it.toIntOrNull(16) }
        return ParsedLine(header, bytes)
    }

    private fun canFrame(header: String, bytes: List<Int>, type: FrameType, typeByte: Int): Frame {
        if (bytes.size < 6 || bytes.size > 12) {
            obdError("Invalid frame size: ${bytes.size} bytes", LogCategory.Parsing)
        }
        val dataLen = when (type) {
            FrameType.SingleFrame -> typeByte and 0x0F
            FrameType.FirstFrame -> ((typeByte and 0x0F) shl 8) or bytes[1]
            else -> null
        }
        val seqIndex = if (type == FrameType.ConsecutiveFrame) typeByte and 0x0F else 0
        return Frame(canonicalRaw(header, bytes), bytes, type, dataLen, seqIndex)
    }

    private fun legacyFrame(trimmed: String, bytes: List<Int>, hadCanHeader: Boolean, type: FrameType?): Frame? {
        if (hadCanHeader && type == null) {
            obdError("Invalid frame type detected", LogCategory.Parsing)
        }
        if (bytes.size < 2) return null
        val legacyData = bytes.dropLast(1)
        return Frame(trimmed, legacyData, FrameType.SingleFrame, legacyData.size, 0)
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
            val isCan = f.raw.startsWith("7E8") || f.raw.startsWith("7E9") // Simplified
            if (isCan) {
                val isoPayload = f.data.drop(1).take(f.dataLen ?: 0)
                if (isoPayload.isNotEmpty()) {
                    messages.add(Message(listOf(f), isoPayload))
                }
            } else if (f.data.size >= 1) {
                messages.add(Message(listOf(f), f.data.drop(1)))
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
