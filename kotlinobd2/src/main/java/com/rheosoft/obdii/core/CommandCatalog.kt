package com.rheosoft.obdii.core

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

/**
 * Resolves OBDPIDs.json-style `pid.command` aliases to wire-format hex IDs.
 * Also exposes dynamic command metadata loaded from shared resources.
 */
object CommandCatalog {
    private val gson = Gson()
    private val aliasMaps: Map<String, Map<String, String>> = loadAliasMaps()
    private val commandRows: List<CommandRow> = loadCommandRows()

    val allCommands: Map<String, CommandRow> by lazy {
        commandRows.associateBy { it.command.uppercase() }
    }

    val pidGetterCommands: List<String> by lazy {
        commandRows.asSequence()
            .filter {
                val desc = it.description.lowercase()
                desc.startsWith("supported pids [") || desc.startsWith("supported mids [")
            }
            .map { it.command.uppercase() }
            .toList()
    }

    fun resolveCommandId(aliasOrId: String, pidType: String? = null): String {
        val normalized = aliasOrId.trim()
        if (normalized.isEmpty()) return ""
        val upper = normalized.uppercase()
        if (upper.matches(Regex("^[0-9A-F]{2,6}$"))) return upper
        val section = if (pidType.equals("GMmode22", ignoreCase = true)) "GMmode22" else "mode1"
        val map = aliasMaps[section].orEmpty()
        return map[normalized] ?: normalized
    }

    private fun loadAliasMaps(): Map<String, Map<String, String>> {
        val stream = CommandCatalog::class.java.getResourceAsStream("/command_aliases.json")
            ?: error(
                "command_aliases.json not found on classpath. " +
                    "Ensure ../swiftobd2/Sources/SwiftOBD2/Resources is included as a kotlinobd2 resource root."
            )
        val type = object : TypeToken<Map<String, Map<String, String>>>() {}.type
        return stream.use { s ->
            gson.fromJson(InputStreamReader(s, StandardCharsets.UTF_8), type)
        }
    }

    private fun loadCommandRows(): List<CommandRow> {
        val stream = CommandCatalog::class.java.getResourceAsStream("/commands.enriched.json")
            ?: error(
                "commands.enriched.json not found on classpath. " +
                    "Ensure ../swiftobd2/Sources/SwiftOBD2/Resources is included as a kotlinobd2 resource root."
            )
        val type = object : TypeToken<List<CommandRow>>() {}.type
        return stream.use { s ->
            gson.fromJson(InputStreamReader(s, StandardCharsets.UTF_8), type)
        }
    }

    data class CommandRow(
        val command: String,
        val description: String,
        val bytes: Int,
        val live: Boolean = false,
        val maxValue: Double = 100.0,
        val minValue: Double = 0.0,
        val decoder: Map<String, Any>? = null
    )
}
