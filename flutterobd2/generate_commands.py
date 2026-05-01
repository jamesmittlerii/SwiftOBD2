from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent
SWIFT_RESOURCES = ROOT.parent / "Sources" / "SwiftOBD2" / "Resources"
DATA_DIR = ROOT / "lib" / "src" / "data"

DATA_DIR.mkdir(parents=True, exist_ok=True)

shutil.copy2(SWIFT_RESOURCES / "commands.enriched.json", DATA_DIR / "commands.enriched.json")
shutil.copy2(SWIFT_RESOURCES / "command_aliases.json", DATA_DIR / "command_aliases.json")

print("Copied commands.enriched.json and command_aliases.json into flutterobd2 assets.")
