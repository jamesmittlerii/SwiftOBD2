import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "SwiftOBD2" / "Resources"
COMMANDS_JSON = RESOURCES / "commands.json"
ALIASES_JSON = RESOURCES / "command_aliases.json"
ENRICHED_JSON = RESOURCES / "commands.enriched.json"


def derive_pid_getters(rows: list[dict]) -> set[str]:
    getter_commands = set()
    for row in rows:
        description = (row.get("description") or "").lower()
        if "supported pids [" in description or "supported mids [" in description:
            getter_commands.add((row.get("command") or "").upper())
    return getter_commands


def main() -> None:
    commands = json.loads(COMMANDS_JSON.read_text(encoding="utf-8"))
    aliases = json.loads(ALIASES_JSON.read_text(encoding="utf-8"))
    enriched = json.loads(ENRICHED_JSON.read_text(encoding="utf-8"))

    base_set = {(c["command"].upper(), c["description"]) for c in commands}
    enriched_set = {(c["command"].upper(), c["description"]) for c in enriched}
    assert base_set == enriched_set, "commands.enriched.json diverges from commands.json entries"

    for row in enriched:
        swift_meta = row.get("swift") or {}
        assert swift_meta.get("type"), f"Missing swift.type for command {row.get('command')}"
        assert swift_meta.get("decoderKey"), f"Missing swift.decoderKey for command {row.get('command')}"

    mode1_alias_values = {v.upper() for v in aliases.get("mode1", {}).values()}
    gm_alias_values = {v.upper() for v in aliases.get("GMmode22", {}).values()}
    enriched_by_command = {row["command"].upper(): row for row in enriched}

    known_commands = {row["command"].upper() for row in enriched}

    for command in mode1_alias_values:
        if command not in known_commands:
            continue
        swift_case = (enriched_by_command.get(command, {}).get("swift") or {}).get("case")
        assert swift_case, f"Missing swift.case for mode1 alias command {command}"

    for command in gm_alias_values:
        if command not in known_commands:
            continue
        swift_case = (enriched_by_command.get(command, {}).get("swift") or {}).get("case")
        assert swift_case, f"Missing swift.case for GM alias command {command}"

    assert derive_pid_getters(commands) == derive_pid_getters(enriched), "PID getter derivation changed"
    print("commands.enriched.json parity checks passed")


if __name__ == "__main__":
    main()
