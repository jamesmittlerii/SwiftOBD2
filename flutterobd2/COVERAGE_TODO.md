# Flutter OBD2 Coverage TODO

Generated on 2026-05-08 with:

```powershell
flutter test --coverage
```

All current tests pass: 55/55. LCOV line coverage for Dart sources is **72.9%** (`1178 / 1617` executable lines). This is line coverage only; branch and function coverage are not currently reported by the Flutter LCOV output.

## Current Coverage

| File | Covered | Coverage |
| --- | ---: | ---: |
| `lib/src/comm_protocol.dart` | 7 / 7 | 100.0% |
| `lib/src/commands/obd_command.dart` | 5 / 5 | 100.0% |
| `lib/src/configuration_service.dart` | 6 / 6 | 100.0% |
| `lib/src/data/trouble_code_catalog.dart` | 32 / 32 | 100.0% |
| `lib/src/communication/mock_manager.dart` | 301 / 320 | 94.1% |
| `lib/src/commands/commands.dart` | 101 / 112 | 90.2% |
| `lib/src/elm327.dart` | 173 / 205 | 84.4% |
| `lib/src/utils.dart` | 20 / 24 | 83.3% |
| `lib/src/data/codes.dart` | 13 / 16 | 81.2% |
| `lib/src/communication/wifi_manager.dart` | 61 / 76 | 80.3% |
| `lib/src/parser.dart` | 103 / 140 | 73.6% |
| `lib/src/obd2_service.dart` | 124 / 170 | 72.9% |
| `lib/src/utils/logger.dart` | 8 / 12 | 66.7% |
| `lib/src/decoders.dart` | 200 / 361 | 55.4% |
| `lib/src/communication/ble_manager.dart` | 20 / 131 | 15.3% |

`lib/flutter_obd2.dart` is a barrel export and has no executable LCOV entry.

## Assessment

The tests cover the core happy paths for command loading, several decoders, CAN/legacy parsing, ELM327 adapter setup, supported PID discovery, one continuous-update stream behavior, service configuration/state/error handling, mock transport behavior, and Wi-Fi socket behavior. That gives useful protection around common demo-mode and Wi-Fi reads.

The primary remaining coverage gap is BLE, which still needs an adapter/facade to test without hardware. Decoder edge cases and parser malformed-frame coverage are the next best pure unit-test wins. Service-level multi-PID request behavior and continuous-update backoff are still only partially covered.

Recommended next target: raise line coverage to **80%+** by adding the BLE test adapter, expanding decoder/parser edge cases, and covering the remaining service multi-PID/backoff branches.

## Priority TODOs

### P0: Add a Coverage Gate

- [ ] Add a script or CI step that runs `flutter test --coverage`.
- [ ] Parse `coverage/lcov.info` and fail below an initial floor of 70%.
- [ ] Raise the floor as the TODOs below land: 75%, then 80%.
- [ ] Keep generated `coverage/` artifacts out of source control unless the repo intentionally tracks baselines.

### P0: Cover `Obd2Service`

- [x] Test constructor behavior for explicit `bluetooth`, `wifi`, and `demo` connection types.
- [x] Test restored persisted connection type using `SharedPreferences.setMockInitialValues`.
- [x] Test `setConnectionType` for same-type persistence, type switching, state reset, and `persist: false`.
- [x] Test `scanForPeripherals` emits `true` then `false` even when the underlying scan throws.
- [x] Test `connectToPeripheral` updates `connectedPeripheralPublisher` and delegates to `Elm327`.
- [x] Test `requestPID` for DTC mode `03`.
- [x] Test `requestPID` empty-result cases: no protocol, parser returns no messages, null data, empty payload, and decoder returns null.
- [x] Test `_extractDecodePayload` behavior indirectly with mode `01`, mode `09`, already-stripped payloads, malformed commands, and empty data.
- [ ] Test `requestPIDs` for empty input, missing protocol, short segments, successful composite decode, and partial decode.
- [ ] Test continuous updates backoff behavior when a PID request fails and recovery behavior after success.
- [x] Test service error wrapping for `startConnection`, `scanForTroubleCodes`, `clearTroubleCodes`, and `sendCommand`.

### P0: Cover `MockManager`

- [x] Test connection lifecycle: connect, disconnect, state stream emissions, and command failure when disconnected.
- [x] Test AT command handling: `ATH1`, `ATH0`, `ATE1`, `ATE0`, `ATZ`, `ATDPN`, `ATRV`, valid `ATSTxx`, invalid `ATSTxx`, and generic `AT*`.
- [x] Test echo and header modes alter returned frames as expected.
- [x] Test every simulated PID response currently implemented in the `switch`.
- [x] Test VIN (`0902`), DTC scan (`03`), clear codes (`04`), and unknown-command `NO DATA`.
- [x] Test serialized command execution by issuing concurrent requests and asserting ordered completion.
- [x] Add broad sanity assertions for generated values: RPM, speed, temperatures, pressures, voltage, fuel trim, O2, catalyst temp, lambda, distance, runtime, and fuel level remain in valid byte ranges.

### P1: Cover `WifiManager`

- [ ] Extract response parsing into a small testable helper or mark it `@visibleForTesting`.
- [x] Test response parsing for prompt removal, CR/LF variants, blank lines, and multiple frames.
- [x] Use a local `ServerSocket` in tests to cover connect, command write with `\r`, response completion on `>`, and disconnect.
- [ ] Test timeout/retry behavior with an injected or shortened timeout.
- [x] Test socket error and remote close complete pending messages with errors and emit the expected connection states.
- [x] Test command serialization under concurrent `sendCommand` calls.

### P1: Make BLE Testable, Then Cover It

- [ ] Introduce a small BLE platform adapter interface around `FlutterBluePlus`, `BluetoothDevice`, services, and characteristics.
- [ ] Unit test scan result filtering and discovered peripheral stream updates through the adapter.
- [ ] Test explicit-device connect vs scan-for-first-device connect.
- [ ] Test service UUID matching for common OBD UUIDs and fallback characteristic discovery.
- [ ] Test write-with-response vs write-without-response command paths.
- [ ] Test notification chunk assembly, prompt detection, parser cleanup, timeout/retry behavior, disconnect cleanup, and pending-message failure.

### P1: Expand `Elm327`

- [x] Test `Elm327Error.toString`, static error instances, and factory constructors.
- [ ] Test `dispose` cancels the connection-state subscription.
- [x] Test `_okResponse` failure indirectly through `adapterInitialization`.
- [x] Test adapter initialization failure when any required startup command fails.
- [x] Test preferred protocol success and fallback when preferred protocol fails.
- [x] Test automatic protocol detection failure falling back to manual detection.
- [x] Test manual protocol detection success, skip of `ObdProtocol.none`, and no-protocol-found failure.
- [ ] Test ECU map population for empty, single ECU, engine/transmission pair, no engine ECU, and unknown extra ECUs.
- [ ] Test supported PID parsing for stripped vs full `41 <pid> ...` payloads and empty/bad responses.
- [x] Test VIN null cases: missing command, no protocol, empty messages, null data, and send failures.
- [x] Test `getStatus`, `scanForTroubleCodes`, `clearTroubleCodes`, and `CanProtocol` legacy/CAN parser selection.

### P1: Expand Decoder Coverage

- [ ] Add table-driven tests for every decoder class/function exported by `decoders.dart`.
- [ ] Add invalid-length and boundary-value cases for each decoder.
- [ ] Cover metric and imperial unit paths where supported.
- [ ] Cover DTC decoding edge cases: all-zero padding, odd byte counts, ECU grouping expectations, pending/permanent/current code variants, and unknown catalog entries.
- [ ] Add regression vectors copied from Swift/Kotlin tests where parity matters.

### P2: Parser, Commands, Utils, Config

- [ ] Add parser tests for malformed frames, whitespace variants, multi-frame ordering, invalid hex, extended IDs, and legacy protocol edge cases.
- [ ] Add command catalog tests for alias loading, missing assets, duplicate command IDs, decode dispatch, and command metadata completeness.
- [x] Add `ConfigurationService` tests with `SharedPreferences.setMockInitialValues`.
- [x] Add `ConnectionState.description` and `isConnected` tests.
- [ ] Add logger tests for log-level filtering and category formatting.
- [ ] Add `utils.dart` tests for uncovered edge cases and invalid input handling.

## Suggested Implementation Order

1. BLE adapter abstraction and unit tests.
2. Decoder/parser edge-case expansion and parity vectors.
3. Remaining service multi-PID and continuous-update backoff branches.
4. Coverage gate script/CI integration.

## Notes

- Avoid tests that depend on real BLE hardware, Wi-Fi adapters, wall-clock timing, or live vehicles.
- Prefer fake `CommProtocol` implementations for service and ELM327 tests.
- Keep timing-sensitive tests short by injecting durations or extracting retry/backoff helpers where needed.
- For communication classes, test state streams and pending-completer cleanup as first-class behavior, not just returned values.
