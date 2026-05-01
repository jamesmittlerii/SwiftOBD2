package com.rheosoft.obdii.core

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.InputStreamReader
import java.nio.charset.StandardCharsets

/**
 * Resolves OBDPIDs.json-style `pid.command` aliases to wire-format hex IDs.
 *
 * Alias tables live in [command_aliases.json] (SwiftOBD2 shared Resources), not in code.
 */
object CommandCatalog {
    private val gson = Gson()

    private val aliasMaps: Map<String, Map<String, String>> = loadAliasMaps()

    private fun loadAliasMaps(): Map<String, Map<String, String>> {
        val stream = CommandCatalog::class.java.getResourceAsStream("/command_aliases.json")
            ?: error(
                "command_aliases.json not found on classpath. " +
                    "Ensure SwiftOBD2 Sources/SwiftOBD2/Resources is included as a kotlinobd2 resource root.",
            )
        val type = object : TypeToken<Map<String, Map<String, String>>>() {}.type
        return stream.use { s ->
            gson.fromJson(InputStreamReader(s, StandardCharsets.UTF_8), type)
        }
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
}
