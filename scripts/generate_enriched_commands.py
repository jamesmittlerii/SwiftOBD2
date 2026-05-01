import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Sources" / "SwiftOBD2" / "Resources"
COMMANDS_JSON = RESOURCES / "commands.json"
ALIASES_JSON = RESOURCES / "command_aliases.json"
ENRICHED_JSON = RESOURCES / "commands.enriched.json"


MODE1_MANUAL_CASES = {
    "0100": "pidsA",
    "011D": "O2SensorsALT",
    "0120": "pidsB",
    "0140": "pidsC",
    "014F": "maxValues",
    "0155": "shortO2TrimB1",
    "0156": "longO2TrimB1",
    "0157": "shortO2TrimB2",
    "0158": "longO2TrimB2",
    "015F": "emissionsReq",
}

MODE9_CASES = {
    "0900": "PIDS_9A",
    "0901": "VIN_MESSAGE_COUNT",
    "0902": "VIN",
    "0903": "CALIBRATION_ID_MESSAGE_COUNT",
    "0904": "CALIBRATION_ID",
    "0905": "CVN_MESSAGE_COUNT",
    "0906": "CVN",
}

MODE6_CASES = {
    "0600": "MIDS_A",
    "0620": "MIDS_B",
    "0640": "MIDS_C",
    "0660": "MIDS_D",
    "0680": "MIDS_E",
    "06A0": "MIDS_F",
}

PROTOCOL_CASES = {
    "ATSP0": "ATSP0",
    "ATSP6": "ATSP6",
}

GENERAL_CASES = {
    "ATD": "ATD",
    "ATZ": "ATZ",
    "ATRV": "ATRV",
    "ATL0": "ATL0",
    "ATE0": "ATE0",
    "ATH1": "ATH1",
    "ATH0": "ATH0",
    "ATAT1": "ATAT1",
    "ATSTFF": "ATSTFF",
    "ATDPN": "ATDPN",
}


def infer_type(command: str) -> str:
    if command in GENERAL_CASES:
        return "general"
    if command in PROTOCOL_CASES:
        return "protocols"
    if command == "03":
        return "mode3"
    if command == "04":
        return "mode4"
    if command.startswith("01"):
        return "mode1"
    if command.startswith("06"):
        return "mode6"
    if command.startswith("09"):
        return "mode9"
    if command.startswith("22"):
        return "GMmode22"
    return "unknown"


def infer_case(command: str, cmd_type: str, mode1_rev: dict, gm_rev: dict) -> str | None:
    if cmd_type == "general":
        return GENERAL_CASES.get(command)
    if cmd_type == "protocols":
        return PROTOCOL_CASES.get(command)
    if cmd_type == "mode3":
        return "GET_DTC" if command == "03" else None
    if cmd_type == "mode4":
        return "CLEAR_DTC" if command == "04" else None
    if cmd_type == "mode1":
        return mode1_rev.get(command) or MODE1_MANUAL_CASES.get(command)
    if cmd_type == "mode6":
        return MODE6_CASES.get(command)
    if cmd_type == "mode9":
        return MODE9_CASES.get(command)
    if cmd_type == "GMmode22":
        return gm_rev.get(command)
    return None


def main() -> None:
    commands = json.loads(COMMANDS_JSON.read_text(encoding="utf-8"))
    aliases = json.loads(ALIASES_JSON.read_text(encoding="utf-8"))

    mode1_rev = {v.upper(): k for k, v in aliases.get("mode1", {}).items()}
    gm_rev = {v.upper(): k for k, v in aliases.get("GMmode22", {}).items()}

    enriched = []
    for row in commands:
        command = row["command"].upper()
        cmd_type = infer_type(command)
        case_name = infer_case(command, cmd_type, mode1_rev, gm_rev)
        decoder_key = next(iter((row.get("decoder") or {"none": {}}).keys()))

        enriched.append(
            {
                **row,
                "command": command,
                "schemaVersion": 1,
                "swift": {
                    "type": cmd_type,
                    "case": case_name,
                    "decoderKey": decoder_key,
                },
            }
        )

    ENRICHED_JSON.write_text(json.dumps(enriched, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(enriched)} entries to {ENRICHED_JSON}")


if __name__ == "__main__":
    main()
