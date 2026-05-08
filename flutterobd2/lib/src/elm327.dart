import 'dart:async';
import 'package:collection/collection.dart';

import 'comm_protocol.dart';
import 'commands/obd_command.dart';
import 'commands/commands.dart';
import 'decoders.dart';
import 'parser.dart';
import 'utils.dart';
import 'utils/logger.dart';

class Elm327Error implements Exception {
  final String message;
  Elm327Error(this.message);

  @override
  String toString() => "Elm327Error: $message";

  static final noConnection = Elm327Error("No connection to the device.");
  static final connectionNotReady =
      Elm327Error("The connection is not yet ready.");
  static final encodingError = Elm327Error("Failed to encode command.");
  static final noProtocolFound =
      Elm327Error("No compatible OBD protocol found.");
  static final adapterInitializationFailed =
      Elm327Error("Failed to initialize adapter.");
  static final ignitionOff = Elm327Error("Vehicle ignition is off.");
  static final invalidProtocol =
      Elm327Error("Invalid or unsupported OBD protocol.");
  static final timeout = Elm327Error("Operation timed out.");
  static final unknownError = Elm327Error("An unknown error occurred.");

  static Elm327Error invalidResponse(String msg) =>
      Elm327Error("Invalid response received: $msg");
  static Elm327Error sendFailed(Exception e) =>
      Elm327Error("Failed to send command: $e");
  static Elm327Error receiveFailed(Exception e) =>
      Elm327Error("Failed to receive response: $e");
  static Elm327Error connectionFailed(String reason) =>
      Elm327Error("Connection failed: $reason");
}

class ObdInfo {
  final String? vin;
  final List<ObdCommand>? supportedPIDs;
  final ObdProtocol? obdProtocol;
  final Map<int, EcuId>? ecuMap;

  ObdInfo({
    this.vin,
    this.supportedPIDs,
    this.obdProtocol,
    this.ecuMap,
  });
}

class Elm327 {
  final CommProtocol _comm;
  ObdServiceDelegate? obdDelegate;

  CanProtocol? canProtocol;
  List<String> _r100 = [];

  ConnectionState _connectionState = ConnectionState.disconnected;
  StreamSubscription<ConnectionState>? _connectionSub;

  Elm327(this._comm) {
    _connectionSub = _comm.connectionStatePublisher.listen((state) {
      connectionState = state;
    });
  }

  void dispose() {
    _connectionSub?.cancel();
  }

  ConnectionState get connectionState => _connectionState;

  set connectionState(ConnectionState state) {
    _connectionState = state;
    obdDelegate?.connectionStateChanged(state);
    _comm.obdDelegate?.connectionStateChanged(state);
  }

  Future<void> connectToAdapter(
      {required double timeout, Object? peripheral}) async {
    await _comm.connectAsync(timeout: timeout, peripheral: peripheral);
  }

  void stopConnection() {
    _comm.disconnectPeripheral();
    connectionState = ConnectionState.disconnected;
  }

  Future<List<String>> sendCommand(String message, {int retries = 1}) async {
    ObdLog.debug('>> $message', category: 'Communication');
    final response = await _comm.sendCommand(message, retries: retries);
    ObdLog.debug('<< ${response.join(", ")}', category: 'Communication');
    return response;
  }

  Future<List<String>> _okResponse(String message) async {
    final response = await sendCommand(message);
    if (response.join().contains("OK")) {
      return response;
    } else {
      throw Elm327Error.invalidResponse(
          "message: $message, response: $response");
    }
  }

  Future<void> adapterInitialization() async {
    ObdLog.info('Initializing adapter...', category: 'Service');
    try {
      await sendCommand("ATZ");
      await Future.delayed(const Duration(milliseconds: 300));

      await sendCommand("ATE0");
      await _okResponse("ATS0");
      await _okResponse("ATL0");
      await _okResponse("ATH1");
      await _okResponse("ATSP0");
      await _okResponse("ATAT1");
      await _okResponse("ATAL");
      // Keep startup detection tolerant. Some vehicles need more than the
      // aggressive 40 ms ATST0A timeout while the ELM is finding a protocol.
      await _okResponse("ATST64");
      ObdLog.info('Adapter initialized successfully.', category: 'Service');
    } catch (e) {
      ObdLog.error('Adapter initialization failed: $e', category: 'Service');
      throw Elm327Error.adapterInitializationFailed;
    }
  }

  Future<ObdInfo> setupVehicle(
      {ObdProtocol? preferredProtocol, bool querySupportedPIDs = true}) async {
    ObdLog.info('Setting up vehicle...', category: 'Service');
    final detectedProtocol = await _detectProtocol(preferredProtocol);
    ObdLog.info('Protocol detected: ${detectedProtocol.name}',
        category: 'Service');
    canProtocol = CanProtocol(
        detectedProtocol); // Assume CAN for now, Swift code uses protocol map.

    final vin = await requestVin();
    ObdLog.info('VIN: ${vin ?? "unknown"}', category: 'Service');
    List<ObdCommand>? supportedPIDs;
    Map<int, EcuId>? ecuMap;

    if (querySupportedPIDs) {
      supportedPIDs = await getSupportedPIDs();
      if (canProtocol != null) {
        final messages = canProtocol!.parse(_r100);
        ecuMap = _populateECUMap(messages);
      }
    }

    connectionState = ConnectionState.connectedToVehicle;
    return ObdInfo(
      vin: vin,
      supportedPIDs: supportedPIDs,
      obdProtocol: detectedProtocol,
      ecuMap: ecuMap,
    );
  }

  Future<ObdProtocol> _detectProtocol(ObdProtocol? preferredProtocol) async {
    if (preferredProtocol != null) {
      if (await _testProtocol(preferredProtocol)) {
        return preferredProtocol;
      }
    }

    try {
      return await _detectProtocolAutomatically();
    } catch (e) {
      return await _detectProtocolManually();
    }
  }

  Future<ObdProtocol> _detectProtocolAutomatically() async {
    await _okResponse("ATSP0");
    await Future.delayed(const Duration(seconds: 1));
    await sendCommand("0100");

    final response = await sendCommand("ATDPN");
    if (response.isNotEmpty && response[0].length >= 2) {
      final protocolHex = response[0].substring(1);
      final protocol = ObdProtocol.values
          .firstWhereOrNull((p) => p.cmd == "ATSP$protocolHex");
      if (protocol != null) {
        await _testProtocol(protocol);
        return protocol;
      }
    }
    throw Elm327Error.invalidResponse("Invalid protocol number");
  }

  Future<ObdProtocol> _detectProtocolManually() async {
    for (final p in ObdProtocol.values) {
      if (p == ObdProtocol.none) continue;

      try {
        await _okResponse(p.cmd);
        if (await _testProtocol(p)) {
          return p;
        }
      } catch (_) {}
    }
    throw Elm327Error.noProtocolFound;
  }

  Future<bool> _testProtocol(ObdProtocol protocol) async {
    try {
      final response = await sendCommand("0100", retries: 3);
      bool isValid = response.any((r) => RegExp(r'41\s*00').hasMatch(r));
      if (isValid) {
        _r100 = response;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Map<int, EcuId>? _populateECUMap(List<ParsedMessage> messages) {
    if (messages.isEmpty) return null;

    final ecuMap = <int, EcuId>{};
    if (messages.length == 1) {
      ecuMap[messages.first.ecu.value] = EcuId.engine;
      return ecuMap;
    }

    final foundEngine = _assignKnownEcus(messages, ecuMap);
    if (!foundEngine) _assignMostCompleteEcuAsEngine(messages, ecuMap);
    _assignRemainingEcus(messages, ecuMap);

    return ecuMap;
  }

  bool _assignKnownEcus(
    List<ParsedMessage> messages,
    Map<int, EcuId> ecuMap,
  ) {
    var foundEngine = false;
    for (var msg in messages) {
      final ecuValue = msg.ecu.value;
      if (ecuValue == 0) {
        ecuMap[ecuValue] = EcuId.engine;
        foundEngine = true;
      } else if (ecuValue == 1) {
        ecuMap[ecuValue] = EcuId.transmission;
      }
    }
    return foundEngine;
  }

  void _assignMostCompleteEcuAsEngine(
    List<ParsedMessage> messages,
    Map<int, EcuId> ecuMap,
  ) {
    final best = messages.fold<ParsedMessage?>(null, (current, msg) {
      final currentBits = (current?.data?.length ?? 0) * 8;
      final msgBits = (msg.data?.length ?? 0) * 8;
      return msgBits > currentBits ? msg : current;
    });
    final bestTxId = best?.ecu.value;
    if (bestTxId != null) {
      ecuMap[bestTxId] = EcuId.engine;
    }
  }

  void _assignRemainingEcus(
    List<ParsedMessage> messages,
    Map<int, EcuId> ecuMap,
  ) {
    for (var msg in messages) {
      ecuMap.putIfAbsent(msg.ecu.value, () => EcuId.transmission);
    }
  }

  Future<List<ObdCommand>> getSupportedPIDs() async {
    await Commands.ensureInitialized();
    final pidGetters = Commands.pidGetterCommands
        .map((id) => Commands.allCommands[id])
        .whereType<ObdCommand>()
        .toList();
    List<ObdCommand> supportedPIDs = [];

    for (final getter in pidGetters) {
      try {
        final response = await sendCommand(getter.properties.command);
        final offset =
            int.tryParse(getter.properties.command.substring(2), radix: 16) ??
                0;
        final supported = _parseResponse(response, offset: offset);
        if (supported != null) {
          final commands = Commands.allCommands.values.where(
            (c) =>
                c.properties.command.length >= 4 &&
                supported.contains(c.properties.command.substring(2)),
          );
          supportedPIDs.addAll(commands);
        }
      } catch (_) {}
    }

    supportedPIDs.removeWhere((c) => pidGetters.contains(c));
    return supportedPIDs.toSet().toList();
  }

  Set<String>? _parseResponse(List<String> response, {int offset = 0}) {
    if (canProtocol == null) return null;
    final messages = canProtocol!.parse(response);
    if (messages.isEmpty || messages.first.data == null) return null;

    final raw = messages.first.data!;
    // Expected for Mode 01 support responses: 41 <getterPid> <4-byte bitmap...>
    // Keep parser resilient if a transport already stripped mode/pid bytes.
    final data = (raw.length >= 6 && raw[0] == 0x41)
        ? raw.sublist(2)
        : (raw.length > 4 ? raw.sublist(raw.length - 4) : raw);
    var binaryData = <int>[];
    for (var b in data) {
      for (int i = 7; i >= 0; i--) {
        binaryData.add((b >> i) & 1);
      }
    }
    return _extractSupportedPIDs(binaryData, offset: offset);
  }

  Set<String> _extractSupportedPIDs(List<int> binaryData, {int offset = 0}) {
    final supported = <String>{};
    for (int i = 0; i < binaryData.length; i++) {
      if (binaryData[i] == 1) {
        final pid =
            (offset + i + 1).toRadixString(16).padLeft(2, '0').toUpperCase();
        supported.add(pid);
      }
    }
    return supported;
  }

  Future<String?> requestVin() async {
    await Commands.ensureInitialized();
    final command = Commands.allCommands["0902"];
    if (command == null) return null;

    try {
      final response = await sendCommand(command.properties.command);
      if (canProtocol == null) return null;
      final messages = canProtocol!.parse(response);
      if (messages.isEmpty || messages.first.data == null) return null;

      var vin = String.fromCharCodes(messages.first.data!);
      vin = vin.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      return vin;
    } catch (_) {
      return null;
    }
  }

  Future<DecodeResult?> getStatus() async {
    await Commands.ensureInitialized();
    final statusCommand = Commands.allCommands["0101"];
    if (statusCommand == null) return null;

    final response = await sendCommand(statusCommand.properties.command);
    if (canProtocol == null) return null;
    final messages = canProtocol!.parse(response);
    if (messages.isEmpty || messages.first.data == null) return null;

    final data = messages.first.data!.sublist(1);
    return statusCommand.properties.decode(data, MeasurementUnit.metric);
  }

  Future<Map<EcuId, List<TroubleCodeMetadata>>> scanForTroubleCodes() async {
    await Commands.ensureInitialized();
    final dtcs = <EcuId, List<TroubleCodeMetadata>>{};
    final command = Commands.allCommands["03"];
    if (command == null) return dtcs;

    final response = await sendCommand(command.properties.command);
    if (canProtocol == null) return dtcs;
    final messages = canProtocol!.parse(response);

    for (final message in messages) {
      if (message.data == null) continue;
      final raw = message.data!;
      // Mode 3 response: [0x43, count, dtcA_hi, dtcA_lo, dtcB_hi, dtcB_lo, ...]
      // Strip the mode byte (0x43) AND the DTC count byte before decoding.
      if (raw.length < 2) continue;
      final result =
          command.properties.decode(raw.sublist(2), MeasurementUnit.metric);
      if (result != null && result.troubleCodes != null) {
        dtcs[message.ecu] = result.troubleCodes!;
      }
    }
    return dtcs;
  }

  Future<void> clearTroubleCodes() async {
    await Commands.ensureInitialized();
    final command = Commands.allCommands["04"];
    if (command != null) {
      await sendCommand(command.properties.command);
    }
  }

  Future<void> scanForPeripherals() async {
    await _comm.scanForPeripherals();
  }
}

class CanProtocol {
  final ObdProtocol protocol;
  CanProtocol(this.protocol);

  List<ParsedMessage> parse(List<String> lines) {
    if (_usesLegacyParser(protocol)) {
      return LegacyParser(lines).messages;
    }
    return CANParser(lines, idBits: protocol.idBits).messages;
  }

  bool _usesLegacyParser(ObdProtocol p) {
    switch (p) {
      case ObdProtocol.protocol1:
      case ObdProtocol.protocol2:
      case ObdProtocol.protocol3:
      case ObdProtocol.protocol4:
      case ObdProtocol.protocol5:
        return true;
      default:
        return false;
    }
  }
}
