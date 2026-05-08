import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'comm_protocol.dart';
import 'elm327.dart';
import 'communication/ble_manager.dart';
import 'communication/mock_manager.dart';
import 'communication/wifi_manager.dart';
import 'commands/obd_command.dart';
import 'configuration_service.dart';
import 'decoders.dart';
import 'data/trouble_code_catalog.dart';
import 'utils.dart';
import 'parser.dart';
import 'utils/logger.dart';

enum ConnectionType {
  bluetooth,
  wifi,
  demo,
}

class Obd2Service implements ObdServiceDelegate {
  final _connectionStateController =
      StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionStatePublisher =>
      _connectionStateController.stream;
  final _isScanningController = StreamController<bool>.broadcast();
  Stream<bool> get isScanningPublisher => _isScanningController.stream;
  final _connectedPeripheralController = StreamController<Object?>.broadcast();
  Stream<Object?> get connectedPeripheralPublisher =>
      _connectedPeripheralController.stream;
  final _discoveredPeripheralsController =
      StreamController<List<Object>>.broadcast();
  Stream<List<Object>> get discoveredPeripheralsPublisher =>
      _discoveredPeripheralsController.stream;

  ConnectionState connectionState = ConnectionState.disconnected;
  bool isScanning = false;
  Object? connectedPeripheral;
  List<Object> discoveredPeripherals = const [];
  ConnectionType connectionType;

  late Elm327 elm327;
  final ConfigurationService _configurationService;
  StreamSubscription<Object?>? _bleConnectedPeripheralSub;
  StreamSubscription<List<Object>>? _bleDiscoveredPeripheralsSub;

  final List<ObdCommand> _pidList = [];

  Obd2Service({
    this.connectionType = ConnectionType.bluetooth,
    String? host,
    int? port,
    ConfigurationService? configurationService,
  }) : _configurationService = configurationService ?? ConfigurationService() {
    unawaited(TroubleCodeCatalog.ensureLoaded());
    _initializeElm327(host, port);
    // Respect explicit constructor parameters from host apps.
    // Only restore saved settings when the caller used pure defaults.
    if (connectionType == ConnectionType.bluetooth &&
        host == null &&
        port == null) {
      unawaited(_restoreConnectionType(host: host, port: port));
    }
  }

  void _initializeElm327(String? host, int? port) {
    _bleConnectedPeripheralSub?.cancel();
    _bleDiscoveredPeripheralsSub?.cancel();
    CommProtocol comm;
    switch (connectionType) {
      case ConnectionType.bluetooth:
        comm = BleManager();
        break;
      case ConnectionType.wifi:
        comm = WifiManager(host: host ?? "192.168.0.10", port: port ?? 35000);
        break;
      case ConnectionType.demo:
        comm = MockManager();
        break;
    }
    elm327 = Elm327(comm);
    elm327.obdDelegate = this;
    if (comm is BleManager) {
      _bleConnectedPeripheralSub =
          comm.connectedPeripheralPublisher.listen((peripheral) {
        connectedPeripheral = peripheral;
        _connectedPeripheralController.add(peripheral);
      });
      _bleDiscoveredPeripheralsSub =
          comm.discoveredPeripheralsPublisher.listen((peripherals) {
        discoveredPeripherals = peripherals;
        _discoveredPeripheralsController.add(peripherals);
      });
    }
  }

  Future<void> _restoreConnectionType({String? host, int? port}) async {
    final savedName = await _configurationService.getConnectionTypeName();
    final saved = ConnectionType.values.firstWhere(
      (value) => value.name == savedName,
      orElse: () => ConnectionType.bluetooth,
    );
    if (saved != connectionType) {
      await setConnectionType(saved, host: host, port: port, persist: false);
    } else {
      await _configurationService.setConnectionTypeName(connectionType.name);
    }
  }

  @override
  void connectionStateChanged(ConnectionState state) {
    ObdLog.info('connection state changed to ${state.name}',
        category: 'Service');
    connectionState = state;
    _connectionStateController.add(state);
    if (state == ConnectionState.disconnected) {
      connectedPeripheral = null;
      _connectedPeripheralController.add(null);
    }
  }

  Future<ObdInfo> startConnection(
      {ObdProtocol? preferredProtocol,
      double timeout = 30.0,
      bool querySupportedPIDs = true,
      Object? peripheral}) async {
    try {
      await elm327.connectToAdapter(timeout: timeout, peripheral: peripheral);
      await elm327.adapterInitialization();
      return await elm327.setupVehicle(
          preferredProtocol: preferredProtocol,
          querySupportedPIDs: querySupportedPIDs);
    } catch (e) {
      throw ObdServiceException(
        ObdServiceErrorType.adapterConnectionFailed,
        "Failed to connect to adapter/vehicle",
        e,
      );
    }
  }

  void stopConnection() {
    elm327.stopConnection();
  }

  Future<void> setConnectionType(
    ConnectionType newType, {
    String? host,
    int? port,
    bool persist = true,
  }) async {
    if (connectionType == newType) {
      if (persist) {
        await _configurationService.setConnectionTypeName(newType.name);
      }
      return;
    }
    stopConnection();
    connectionType = newType;
    connectedPeripheral = null;
    discoveredPeripherals = const [];
    _connectedPeripheralController.add(null);
    _discoveredPeripheralsController.add(const []);
    _initializeElm327(host, port);
    if (persist) {
      await _configurationService.setConnectionTypeName(newType.name);
    }
  }

  Future<void> scanForPeripherals() async {
    ObdLog.info('starting scan for peripherals...', category: 'Service');
    isScanning = true;
    _isScanningController.add(true);
    try {
      await elm327.scanForPeripherals();
    } finally {
      isScanning = false;
      _isScanningController.add(false);
    }
  }

  Future<void> connectToPeripheral(
      {required Object peripheral, double timeout = 30.0}) async {
    connectedPeripheral = peripheral;
    _connectedPeripheralController.add(peripheral);
    await elm327.connectToAdapter(timeout: timeout, peripheral: peripheral);
  }

  void addPID(ObdCommand pid) {
    if (!_pidList.contains(pid)) {
      _pidList.add(pid);
    }
  }

  void removePID(ObdCommand pid) {
    _pidList.remove(pid);
  }

  Future<Map<ObdCommand, DecodeResult>> requestPID(ObdCommand command,
      {MeasurementUnit unit = MeasurementUnit.metric}) async {
    if (command.properties.command == "03") {
      final dtcsByECU = await elm327.scanForTroubleCodes();
      return {
        command: DecodeResult(
          troubleCodesByEcu: dtcsByECU,
          troubleCodes: dtcsByECU.values.expand((x) => x).toList(),
        ),
      };
    }

    final response =
        await _sendCommandInternal(command.properties.command, retries: 1);
    if (elm327.canProtocol == null) {
      return {};
    }

    final messages = elm327.canProtocol!.parse(response);
    if (messages.isEmpty || messages.first.data == null) {
      return {};
    }

    final messageData = messages.first.data!;
    final payload =
        _extractDecodePayload(command.properties.command, messageData);
    if (payload.isEmpty) {
      return {};
    }
    final result = command.properties.decode(payload, unit);
    if (result != null) {
      return {command: result};
    }
    return {};
  }

  Uint8List _extractDecodePayload(String command, Uint8List data) {
    if (data.isEmpty) {
      return Uint8List(0);
    }

    final pid = _parsePid(command);
    if (pid == null) {
      return data;
    }

    if (command.startsWith("01")) {
      return _extractMode1Payload(pid, data);
    }
    if (command.startsWith("09")) {
      return _extractServicePayload(0x49, pid, data);
    }

    // Fallback for already-stripped payloads.
    return data;
  }

  int? _parsePid(String command) {
    if (command.length < 4) {
      return null;
    }
    return int.tryParse(command.substring(2, 4), radix: 16);
  }

  Uint8List _extractMode1Payload(int pid, Uint8List data) {
    final servicePayload = _extractServicePayload(0x41, pid, data);
    if (!identical(servicePayload, data)) {
      return servicePayload;
    }
    if (data[0] == pid) {
      return Uint8List.fromList(data.sublist(1));
    }
    return data;
  }

  Uint8List _extractServicePayload(int service, int pid, Uint8List data) {
    if (data.length >= 2 && data[0] == service && data[1] == pid) {
      return Uint8List.fromList(data.sublist(2));
    }
    return data;
  }

  Future<Map<ObdCommand, DecodeResult>> requestPIDs(
    List<ObdCommand> commands, {
    MeasurementUnit unit = MeasurementUnit.metric,
  }) async {
    if (commands.isEmpty) {
      return {};
    }

    final composite =
        "01${commands.map((c) => c.properties.command.substring(2)).join()}";
    final response = await _sendCommandInternal(composite, retries: 1);
    if (elm327.canProtocol == null) {
      return {};
    }

    final messages = elm327.canProtocol!.parse(response);
    if (messages.isEmpty || messages.first.data == null) {
      return {};
    }

    final results = <ObdCommand, DecodeResult>{};
    final data = messages.first.data!;
    var offset = 0;
    for (final command in commands) {
      final size = command.properties.bytes;
      if (offset + size > data.length) {
        break;
      }
      final segment = data.sublist(offset, offset + size);
      offset += size;

      final pidSize = (command.properties.command.length ~/ 2) - 1;
      if (segment.length <= pidSize) {
        continue;
      }
      final decoded = command.properties.decode(segment.sublist(pidSize), unit);
      if (decoded != null) {
        results[command] = decoded;
      }
    }
    return results;
  }

  Stream<Map<ObdCommand, DecodeResult>> startContinuousUpdates({
    List<ObdCommand>? pids,
    MeasurementUnit unit = MeasurementUnit.metric,
    Duration interval = const Duration(seconds: 1),
  }) async* {
    final commandsToRun = List<ObdCommand>.of(pids ?? _pidList);
    var currentIntervalMs = interval.inMilliseconds;
    final minIntervalMs = currentIntervalMs < 200 ? 200 : currentIntervalMs;
    final maxIntervalMs = (interval.inMilliseconds * 4) > 2000
        ? (interval.inMilliseconds * 4)
        : 2000;
    var inFlight = false;

    while (_canRunContinuousUpdates) {
      if (inFlight) {
        await Future.delayed(Duration(milliseconds: currentIntervalMs));
        continue;
      }

      inFlight = true;
      final cycle = await _requestContinuousUpdateCycle(commandsToRun, unit);
      currentIntervalMs = _nextContinuousInterval(
        currentIntervalMs,
        minIntervalMs: minIntervalMs,
        maxIntervalMs: maxIntervalMs,
        hadFailure: cycle.hadFailure,
      );

      inFlight = false;
      yield cycle.results;
      await Future.delayed(Duration(milliseconds: currentIntervalMs));
    }
  }

  bool get _canRunContinuousUpdates =>
      connectionState == ConnectionState.connectedToVehicle ||
      connectionState == ConnectionState.connectedToAdapter;

  Future<_ContinuousUpdateCycle> _requestContinuousUpdateCycle(
    List<ObdCommand> commands,
    MeasurementUnit unit,
  ) async {
    var hadFailure = false;
    final results = <ObdCommand, DecodeResult>{};
    for (final pid in commands) {
      try {
        results.addAll(await requestPID(pid, unit: unit));
      } catch (_) {
        hadFailure = true;
      }
    }
    return _ContinuousUpdateCycle(results, hadFailure);
  }

  int _nextContinuousInterval(
    int currentIntervalMs, {
    required int minIntervalMs,
    required int maxIntervalMs,
    required bool hadFailure,
  }) {
    final adjusted = hadFailure
        ? (currentIntervalMs * 1.5).round()
        : (currentIntervalMs * 0.9).round();
    return adjusted.clamp(minIntervalMs, maxIntervalMs);
  }

  Future<List<ObdCommand>> getSupportedPIDs() async {
    return await elm327.getSupportedPIDs();
  }

  Future<Map<EcuId, List<TroubleCodeMetadata>>> scanForTroubleCodes() async {
    try {
      return await elm327.scanForTroubleCodes();
    } catch (e) {
      throw ObdServiceException(
          ObdServiceErrorType.scanFailed, "Failed to scan trouble codes", e);
    }
  }

  Future<void> clearTroubleCodes() async {
    try {
      await elm327.clearTroubleCodes();
    } catch (e) {
      throw ObdServiceException(
          ObdServiceErrorType.clearFailed, "Failed to clear trouble codes", e);
    }
  }

  Future<DecodeResult?> getStatus() async {
    return await elm327.getStatus();
  }

  Future<List<String>> sendCommand(String command, {int retries = 1}) async {
    return _sendCommandInternal(command, retries: retries);
  }

  Future<List<String>> _sendCommandInternal(String message,
      {int retries = 1}) async {
    try {
      return await elm327.sendCommand(message, retries: retries);
    } catch (e) {
      ObdLog.error('command failed [$message]: $e', category: 'Communication');
      throw ObdServiceException(
        ObdServiceErrorType.commandFailed,
        "Command failed: $message",
        e,
      );
    }
  }

  Future<ConnectionType> getPersistedConnectionType() async {
    final savedName = await _configurationService.getConnectionTypeName();
    return ConnectionType.values.firstWhere(
      (value) => value.name == savedName,
      orElse: () => ConnectionType.bluetooth,
    );
  }
}

class _ContinuousUpdateCycle {
  final Map<ObdCommand, DecodeResult> results;
  final bool hadFailure;

  _ContinuousUpdateCycle(this.results, this.hadFailure);
}

enum ObdServiceErrorType {
  noAdapterFound,
  notConnectedToVehicle,
  adapterConnectionFailed,
  scanFailed,
  clearFailed,
  commandFailed,
  pidMismatch,
}

class ObdServiceException implements Exception {
  final ObdServiceErrorType type;
  final String message;
  final Object? cause;

  ObdServiceException(this.type, this.message, [this.cause]);

  @override
  String toString() =>
      "ObdServiceException($type): $message${cause != null ? ' | cause: $cause' : ''}";
}
