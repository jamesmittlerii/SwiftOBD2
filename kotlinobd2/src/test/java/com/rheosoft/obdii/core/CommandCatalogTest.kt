package com.rheosoft.obdii.core

import kotlin.test.Test
import kotlin.test.assertEquals

class CommandCatalogTest {
    @Test
    fun loads_dynamic_command_catalog_from_json() {
        val rpm = CommandCatalog.allCommands["010C"]
        assertEquals("RPM", rpm?.description)
    }

    @Test
    fun derives_pid_getters_from_command_descriptions() {
        val getters = CommandCatalog.pidGetterCommands.toSet()
        assertEquals(true, getters.contains("0100"))
        assertEquals(true, getters.contains("0600"))
        assertEquals(true, getters.contains("0900"))
    }

    @Test
    fun resolve_mode1_alias_to_hex() {
        assertEquals("010C", CommandCatalog.resolveCommandId("rpm"))
        assertEquals("010C", CommandCatalog.resolveCommandId("rpm", pidType = "mode1"))
    }

    @Test
    fun resolve_GMmode22_overloads_engineOilTemp() {
        assertEquals("015C", CommandCatalog.resolveCommandId("engineOilTemp"))
        assertEquals("221154", CommandCatalog.resolveCommandId("engineOilTemp", pidType = "GMmode22"))
    }

    @Test
    fun resolve_raw_hex_passthrough() {
        assertEquals("010C", CommandCatalog.resolveCommandId("010c"))
        assertEquals("221144", CommandCatalog.resolveCommandId("221144"))
    }
}

