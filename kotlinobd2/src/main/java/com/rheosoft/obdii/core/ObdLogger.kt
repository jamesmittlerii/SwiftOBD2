package com.rheosoft.obdii.core

import java.time.Instant

enum class LogCategory(val label: String) {
    App("App"),
    Service("Service"),
    Communication("Communication"),
    UI("UI"),
    Connection("Connection"),
    Parsing("Parsing"),
    Bluetooth("Bluetooth"),
    Wifi("WiFi"),
    Protocol("Protocol"),
    Performance("Performance"),
    Error("Error")
}

data class LogEntry(
    val timestamp: Instant,
    val category: LogCategory,
    val level: String,
    val message: String
) {
    fun toJson(): String {
        return """
            {
              "timestamp": "$timestamp",
              "category": "${category.label}",
              "level": "$level",
              "message": "${message.replace("\"", "\\\"").replace("\n", "\\n")}"
            }
        """.trimIndent()
    }
}

object ObdLogger {
    private val history = mutableListOf<LogEntry>()
    private const val maxHistory = 1000
    private const val minLevel = "debug"

    var mutesConsole: Boolean = false

    /**
     * Optional delegate for platform-specific logging (e.g. android.util.Log).
     * Takes (message, tag, level).
     */
    var platformLogDelegate: ((String, String, String) -> Unit)? = null

    fun log(message: String, category: LogCategory, level: String) {
        if (getLogLevel(level) < getLogLevel(minLevel)) return

        val entry = LogEntry(
            timestamp = Instant.now(),
            category = category,
            level = level,
            message = message
        )

        synchronized(history) {
            history.add(entry)
            if (history.size > maxHistory) {
                history.removeAt(0)
            }
        }

        val tag = category.label
        platformLogDelegate?.invoke(message, tag, level)

        if (!mutesConsole) {
            val emoji = getEmoji(level)
            val formattedMessage = "[$emoji $tag] $message"
            
            when (level.lowercase()) {
                "error", "warning" -> System.err.println(formattedMessage)
                else -> println(formattedMessage)
            }
        }
    }

    private fun getLogLevel(level: String): Int {
        return when (level.lowercase()) {
            "error" -> 1000
            "warning" -> 900
            "info" -> 800
            "debug" -> 500
            else -> 0
        }
    }

    fun getEmoji(level: String): String {
        return when (level.lowercase()) {
            "error" -> "🔴"
            "warning" -> "🟡"
            "info" -> "🔵"
            "debug" -> "⚪"
            else -> "📝"
        }
    }

    fun getHistory(): List<LogEntry> {
        return synchronized(history) { history.toList() }
    }
}

fun obdInfo(message: String, category: LogCategory = LogCategory.App) {
    ObdLogger.log(message, category, "info")
}

fun obdDebug(message: String, category: LogCategory = LogCategory.App) {
    ObdLogger.log(message, category, "debug")
}

fun obdWarning(message: String, category: LogCategory = LogCategory.App) {
    ObdLogger.log(message, category, "warning")
}

fun obdError(message: String, category: LogCategory = LogCategory.App) {
    ObdLogger.log(message, category, "error")
}
