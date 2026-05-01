# kotlinobd2

Kotlin/JVM OBD library module intended to mirror SwiftOBD2 responsibilities for Android/Kotlin clients.

## Current scope

- Connection state/contracts (`ObdConnectionLibrary`, `ObdService`, `Elm327`)
- Transport abstraction (`CommProtocol`)
- WiFi transport implementation (`WifiManager`)
- Mock transport implementation (`MockComm`)
- BLE transport pipeline (`BleManager`, scanner/peripheral manager/characteristic handler/message processor)
- Platform BLE adapter contract (`BlePlatformAdapter`) for Android-backed implementation injection
- Swift alias to command-ID resolver (`CommandCatalog.resolveCommandId`)

## Next steps

- Port Swift BLE stack helpers (`BLEScanner`, `BLEPeripheralManager`, characteristic handlers) into Kotlin/Android module
- Expand decode stack for full command coverage and DTC/readiness parity
- Publish module artifact for app consumption
- Add unit tests for command alias resolution, connection transitions, and mock PID decoding
