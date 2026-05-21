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

    var minLevel: String = configuredMinLevel()
        set(value) {
            field = normalizeLevel(value)
        }

    var mutesConsole: Boolean = false

    /** Log raw BLE notify chunks and prompt completion (very noisy during PID polling). */
    var verboseBleComms: Boolean = false

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
            val formattedMessage = "[${level.uppercase()} $tag] $message"
            
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


    fun getHistory(): List<LogEntry> {
        return synchronized(history) { history.toList() }
    }

    private fun configuredMinLevel(): String =
        normalizeLevel(
            System.getProperty("obd.log.level")
                ?: System.getenv("OBD_LOG_LEVEL")
                ?: "debug",
        )

    private fun normalizeLevel(level: String): String =
        when (level.trim().lowercase()) {
            "error", "warning", "warn", "info", "debug" -> level.trim().lowercase()
            else -> "debug"
        }.let { if (it == "warn") "warning" else it }
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
