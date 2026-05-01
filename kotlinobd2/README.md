# kotlinobd2

Kotlin/JVM OBD library module intended to mirror SwiftOBD2 responsibilities for Android/Kotlin clients.

## Current scope

Layout mirrors SwiftOBD2 under `Sources/SwiftOBD2` (protocols + Communication + Communication/BLE):

- Root-style API (`ObdConnectionLibrary`, `ObdService`, `Elm327`, `CommunicationTypes`, `CommandCatalog`, …)
- `protocols/` — transport contract (`CommProtocol`) and communication errors
- `communication/` — `MockComm`, `WifiManager`
- `communication/ble/` — `BleManager`, `BlePlatformAdapter`, scanner / peripheral manager / characteristic handler / message processor

- Swift alias to command-ID resolver (`CommandCatalog.resolveCommandId`, backed by `command_aliases.json` in shared Resources)

## Next steps

- Port Swift BLE stack helpers (`BLEScanner`, `BLEPeripheralManager`, characteristic handlers) into Kotlin/Android module
- Expand decode stack for full command coverage and DTC/readiness parity
- Publish module artifact for app consumption
- Add unit tests for command alias resolution, connection transitions, and mock PID decoding
