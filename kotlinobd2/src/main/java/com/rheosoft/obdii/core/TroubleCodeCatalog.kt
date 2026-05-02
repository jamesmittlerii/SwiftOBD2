package com.rheosoft.obdii.core

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName

private data class CodesJson(
    val causes: List<String> = emptyList(),
    val remedies: List<String> = emptyList(),
    val codes: Map<String, CodeEntry> = emptyMap(),
) {
    data class CodeEntry(
        val title: String = "",
        val description: String = "",
        @SerializedName("causeIndexes") val causeIndexes: List<Int> = emptyList(),
        @SerializedName("remedyIndexes") val remedyIndexes: List<Int> = emptyList(),
    )
}

object TroubleCodeCatalog {
    private val entries: Map<String, TroubleCodeMetadata> by lazy {
        val stream = TroubleCodeCatalog::class.java.classLoader.getResourceAsStream("codes.json")
            ?: return@lazy emptyMap()
        runCatching {
            stream.bufferedReader(Charsets.UTF_8).use { reader ->
                val json = Gson().fromJson(reader, CodesJson::class.java)
                json.codes.mapValues { (code, entry) ->
                    TroubleCodeMetadata(
                        code = code,
                        title = entry.title,
                        description = entry.description,
                        severity = determineSeverity(code),
                        causes = entry.causeIndexes.mapNotNull { idx -> json.causes.getOrNull(idx) },
                        remedies = entry.remedyIndexes.mapNotNull { idx -> json.remedies.getOrNull(idx) },
                    )
                }
            }
        }.getOrDefault(emptyMap())
    }

    fun lookup(code: String): TroubleCodeMetadata? = entries[code]

    fun severityFor(code: String): String = determineSeverity(code)

    private fun determineSeverity(code: String): String {
        val criticalCodes = setOf("P0087", "P0088", "P0217", "P0218", "P0219", "P0234", "P0606")
        if (code in criticalCodes || code.startsWith("P030") || code.startsWith("P031")) return "Critical"

        val highPrefixes = listOf("P017", "P032", "P033", "P034", "P035", "P036", "P039")
        val highCodes = setOf("U0121", "U0151")
        if (code in highCodes || highPrefixes.any { code.startsWith(it) } || code.startsWith("P07") || code.startsWith("P08")) {
            return "High"
        }

        val lowPrefixes = listOf("P041", "P042", "P043", "P044", "P045", "P049")
        if (lowPrefixes.any { code.startsWith(it) }) return "Low"

        return "Moderate"
    }
}
