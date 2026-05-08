# Kotlin OBD2 Coverage TODO

Generated on 2026-05-08 with:

```powershell
.\gradlew.bat test jacocoTestReport
```

All current Kotlin tests pass: **56/56**. JaCoCo line coverage is **90.0%** (`1194 / 1326` executable lines).

Reports:

- XML: `build/reports/jacoco/test/jacocoTestReport.xml`
- HTML: `build/reports/jacoco/test/html/index.html`
- Test report: `build/reports/tests/test/index.html`

## Current Coverage

| File | Covered | Coverage |
| --- | ---: | ---: |
| `com/rheosoft/obdii/core/ObdService.kt` | 54 / 54 | 100.0% |
| `com/rheosoft/obdii/core/protocols/CommProtocol.kt` | 6 / 6 | 100.0% |
| `com/rheosoft/obdii/core/TroubleCodeCatalog.kt` | 39 / 40 | 97.5% |
| `com/rheosoft/obdii/core/communication/WifiManager.kt` | 71 / 73 | 97.3% |
| `com/rheosoft/obdii/core/communication/ble/BlePeripheralManager.kt` | 20 / 21 | 95.2% |
| `com/rheosoft/obdii/core/communication/MockComm.kt` | 319 / 319 | 100.0% |
| `com/rheosoft/obdii/core/Parser.kt` | 77 / 82 | 93.9% |
| `com/rheosoft/obdii/core/communication/ble/BleTypes.kt` | 24 / 26 | 92.3% |
| `com/rheosoft/obdii/core/CommunicationTypes.kt` | 11 / 12 | 91.7% |
| `com/rheosoft/obdii/core/CommandCatalog.kt` | 35 / 41 | 85.4% |
| `com/rheosoft/obdii/core/Elm327.kt` | 26 / 31 | 83.9% |
| `com/rheosoft/obdii/core/communication/ble/BleMessageProcessor.kt` | 26 / 31 | 83.9% |
| `com/rheosoft/obdii/core/protocols/ProtocolImplementations.kt` | 31 / 39 | 79.5% |
| `com/rheosoft/obdii/core/communication/ble/BleManager.kt` | 61 / 82 | 74.4% |
| `com/rheosoft/obdii/core/OBDCommand.kt` | 34 / 46 | 73.9% |
| `com/rheosoft/obdii/core/ObdLogger.kt` | 51 / 71 | 71.8% |
| `com/rheosoft/obdii/core/Decoders.kt` | 227 / 229 | 99.1% |
| `com/rheosoft/obdii/core/communication/ble/BleScanner.kt` | 6 / 10 | 60.0% |
| `com/rheosoft/obdii/core/communication/ble/BleCharacteristicHandler.kt` | 21 / 37 | 56.8% |
| `com/rheosoft/obdii/core/ObdProtocol.kt` | 6 / 11 | 54.5% |
| `com/rheosoft/obdii/core/ObdTypes.kt` | 11 / 25 | 44.0% |
| `com/rheosoft/obdii/core/communication/ble/BlePlatformAdapter.kt` | 1 / 9 | 11.1% |

## Assessment

The current test suite gives strong protection to the parser, command catalog, trouble-code catalog, service orchestration, mock transport, Wi-Fi transport, and a subset of BLE plumbing through fake adapter flows. `MockComm.kt` now has full line coverage, including late-session readiness and oscillating mock-value paths. The ELM327 wrapper is partially exercised by setup and supported-PID tests.

The major remaining gaps are deeper BLE edge cases, logger behavior, lightweight data helpers, and additional ELM327 protocol fallback/null paths. BLE manager coverage improved through service-level fake adapter tests, but individual BLE helper classes still need direct unit tests for failure paths and characteristic-selection variants. Decoder line coverage is now strong, with the main residual branch gap being the currently unreachable `L/h` UAS imperial conversion path.

Recommended next target: raise the enforced floor toward **85%+** with direct BLE helper tests plus logger/data helper coverage.

## Priority TODOs

### P0: Keep Gradle Coverage Reproducible

- [x] Add Gradle JaCoCo coverage reporting.
- [x] Generate XML and HTML coverage reports from `.\gradlew.bat test jacocoTestReport`.
- [x] Add a Gradle `jacocoTestCoverageVerification` rule.
- [x] Set the current line coverage floor to 80%.
- [x] Raise the coverage floor to 85% after the next BLE/decoder/logger batch.
- [ ] Add CI/report artifact handling for `build/reports/jacoco/test/html`.
- [ ] Keep generated `build/` reports out of source control.

### P0: Cover `MockComm`

- [x] Test connection lifecycle: `connecting`, `connectedToAdapter`, `disconnected`, and delegate callbacks.
- [x] Test AT command handling: `ATZ`, `ATE0`, `ATE1`, `ATH0`, `ATH1`, startup settings, generic `AT*`, and echo behavior.
- [x] Test header-on/header-off frame formatting.
- [x] Test mode `01` support bitmaps: `0100`, `0120`, `0140`.
- [x] Test all implemented mode `01` live PID responses return valid hex payloads and expected service/PID bytes.
- [x] Test mode `03` multi-frame DTC response and decoded DTC parity.
- [x] Test mode `06` monitor support responses and unknown monitor `NO DATA`.
- [x] Test mode `09` support/VIN responses and unknown mode `09` commands.
- [x] Test mode `22` GM responses and unknown mode `22` commands.
- [x] Test fallback `NO DATA` for unsupported commands.
- [x] Add value-range assertions for generated RPM, speed, temperatures, pressure, voltage, fuel trim, O2, catalyst temperature, lambda, runtime, distance, fuel level, fuel rate, and throttle values.

### P0: Cover `WifiManager`

- [x] Use a local `ServerSocket` in tests to cover successful connect, state flow updates, delegate callbacks, command write with `\r`, response read until `>`, and disconnect cleanup.
- [x] Test response parsing for CR/LF variants, blank lines, echoed commands, and multiple response frames.
- [x] Test `sendCommand` without an active socket throws `CommunicationError`.
- [x] Test empty/prompt-only responses throw `InvalidDataError` wrapped by `CommunicationError`.
- [x] Test retry behavior: first read failure followed by success.
- [x] Test connection timeout maps to `ConnectionTimedOutError`.
- [x] Test connection refusal/other socket errors map to `CommunicationError` and emit `error`.
- [x] Test `scanForPeripherals()` returns an empty list.

### P0: Cover `ObdService`

- [x] Test default demo connection type and initial disconnected state.
- [x] Test `switchConnectionType` no-op for same type/host/port.
- [x] Test switching to Wi-Fi updates host/port, stops the old connection, recreates ELM327, and updates `currentConnectionType`.
- [x] Test switching to Bluetooth with `UnsupportedBleAdapter` and `startConnection()` throws `UnsupportedTransportError`.
- [x] Test `setBleAdapter` no-op for the same adapter.
- [x] Test `setBleAdapter` while Bluetooth is active recreates the BLE-backed ELM327.
- [x] Test `connectionStateChanged` clears `connectedPeripheral` on `disconnected` and `error`.
- [x] Test `startConnection` success with demo mode emits/keeps adapter connection state.
- [x] Test `startConnection` failure sets service state to `error` and clears peripheral.
- [x] Test `stopConnection` moves service state to `disconnected`.
- [x] Test `sendCommand` and `scanForPeripherals` delegation through demo and fake BLE paths.

### P1: Cover BLE Components

- [ ] Build fake `BlePlatformAdapter`, `BlePeripheral`, `BleService`, and `BleCharacteristic` fixtures.
- [ ] Test `UnsupportedBleAdapter` throws `UnsupportedTransportError` for scan/connect operations.
- [ ] Test `BleMessageProcessor` chunk assembly, prompt detection, CR/LF cleanup, timeout, and pending-response failure.
- [ ] Test `BleCharacteristicHandler` read/write characteristic selection, notify/indicate subscription, write-with-response vs write-without-response, and missing-characteristic errors.
- [ ] Test `BlePeripheralScanner` filters/returns expected peripherals and handles timeout/no-result cases.
- [ ] Test `BlePeripheralManager` connect/disconnect state transitions and delegate callbacks.
- [ ] Test `BleManager` scan, connect with explicit peripheral, connect by scanning, command send, disconnect cleanup, and error propagation.

### P1: Expand `Elm327`

- [ ] Test adapter initialization failure on each required startup command.
- [ ] Test protocol detection fallback paths and no-protocol-found behavior.
- [ ] Test preferred protocol success and preferred protocol failure followed by automatic/manual fallback.
- [ ] Test `requestVin` success, null protocol, malformed response, empty response, and transport failure.
- [ ] Test supported PID parsing for full CAN payloads and already-stripped payloads.
- [ ] Test supported PID ranges beyond `0100`: `0120`, `0140`, mode `06`, and mode `09`.
- [ ] Test scan/clear trouble codes success and missing command cases.
- [ ] Test connection-state subscription/delegate propagation and `stopConnection` behavior.

### P1: Expand Decoders and Data Types

- [x] Add table-driven tests for every decoder in `Decoders.kt`, not just the common subset.
- [x] Add invalid-length, empty-data, and boundary-value cases for each decoder.
- [x] Cover metric and imperial unit paths where applicable.
- [x] Cover `DecodeResult.Failure` and `DecodeResult.FuelStatusResult`.
- [x] Cover `FuelStatusDecoder`, `UasDecoder`, `StatusDecoder`, and decoder companion lookup edge cases.
- [x] Test DTC decoding edge cases: all-zero padding, odd byte counts, unknown catalog entries, current/pending/permanent variants, and non-powertrain code families.
- [ ] Add tests for `PIDStats`, `StatusCodeMetadata`, `ECUID`, `FrameType`, and other lightweight data helpers currently under-covered.

### P2: Parser, Catalog, Logger, Protocol Polish

- [ ] Add parser tests for malformed frames, lowercase hex, extra whitespace, bad PCI length, extended CAN IDs, and mixed ECU multi-frame ordering.
- [ ] Add protocol tests for 29-bit CAN protocol implementations currently at 0%.
- [ ] Add command catalog tests for alias misses, GM mode 22 aliases, missing resource handling, duplicate command IDs, and metadata completeness.
- [ ] Add logger tests for log-level filtering, category filtering, subscriber behavior, history clearing, and `LogEntry` fields.
- [ ] Add `CommProtocol` error type tests for message/cause formatting.

## Suggested Implementation Order

1. Direct BLE helper/unit tests with fake platform objects.
2. ELM327 edge paths and decoder/parser parity vectors.
3. Logger and lightweight data helper tests.
4. Raise the JaCoCo verification threshold to 85%.

## Notes

- Avoid tests that depend on real BLE hardware, real Wi-Fi adapters, live vehicles, or long wall-clock waits.
- Prefer local sockets and fake BLE platform adapters for transport behavior.
- Keep timing-sensitive behavior injectable or use coroutine test utilities where possible.
- JaCoCo reports Kotlin/JVM generated classes separately, so file-level coverage is more useful than raw class-level output for triage.
