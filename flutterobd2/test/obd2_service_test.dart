import 'dart:async';

import 'package:flutter_obd2/flutter_obd2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _QuietComm implements CommProtocol {
  final _states = StreamController<ConnectionState>.broadcast();

  @override
  ObdServiceDelegate? obdDelegate;

  @override
  Stream<ConnectionState> get connectionStatePublisher => _states.stream;

  @override
  Future<void> connectAsync(
      {required double timeout, Object? peripheral}) async {
    _states.add(ConnectionState.connectedToAdapter);
  }

  @override
  void disconnectPeripheral() {
    _states.add(ConnectionState.disconnected);
  }

  @override
  Future<void> scanForPeripherals() async {}

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async =>
      const [];
}

class _FakeElm327 extends Elm327 {
  _FakeElm327() : super(_QuietComm());

  Object? connectedPeripheral;
  bool throwOnConnect = false;
  bool throwOnScan = false;
  bool throwOnDtcScan = false;
  bool throwOnClear = false;
  bool throwOnCommand = false;
  List<String> commandResponse = const ['7E8 04 41 0C 0C 80'];
  Map<EcuId, List<TroubleCodeMetadata>> dtcResponse = const {};

  @override
  Future<void> connectToAdapter(
      {required double timeout, Object? peripheral}) async {
    if (throwOnConnect) {
      throw Exception('connect failed');
    }
    connectedPeripheral = peripheral;
  }

  @override
  Future<void> scanForPeripherals() async {
    if (throwOnScan) {
      throw Exception('scan failed');
    }
  }

  @override
  Future<List<String>> sendCommand(String message, {int retries = 1}) async {
    if (throwOnCommand) {
      throw Exception('command failed');
    }
    return commandResponse;
  }

  @override
  Future<Map<EcuId, List<TroubleCodeMetadata>>> scanForTroubleCodes() async {
    if (throwOnDtcScan) {
      throw Exception('dtc failed');
    }
    return dtcResponse;
  }

  @override
  Future<void> clearTroubleCodes() async {
    if (throwOnClear) {
      throw Exception('clear failed');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Obd2Service configuration and state', () {
    test('persists and restores connection type', () async {
      final config = ConfigurationService();
      await config.setConnectionTypeName(ConnectionType.demo.name);

      final service = Obd2Service(configurationService: config);
      await pumpEventQueue(times: 5);

      expect(service.connectionType, ConnectionType.demo);
      expect(await service.getPersistedConnectionType(), ConnectionType.demo);
    });

    test('setConnectionType resets peripheral state and can skip persistence',
        () async {
      final config = ConfigurationService();
      final service = Obd2Service(
        connectionType: ConnectionType.demo,
        configurationService: config,
      );

      final connected = <Object?>[];
      final discovered = <List<Object>>[];
      final connectedSub =
          service.connectedPeripheralPublisher.listen(connected.add);
      final discoveredSub =
          service.discoveredPeripheralsPublisher.listen(discovered.add);

      await service.setConnectionType(ConnectionType.wifi, persist: false);
      await pumpEventQueue();

      expect(service.connectionType, ConnectionType.wifi);
      expect(service.connectedPeripheral, isNull);
      expect(service.discoveredPeripherals, isEmpty);
      expect(connected, contains(null));
      expect(discovered, contains(isEmpty));
      expect(await config.getConnectionTypeName(), isNull);

      await connectedSub.cancel();
      await discoveredSub.cancel();
    });

    test('setConnectionType persists same type without rebuilding connection',
        () async {
      final config = ConfigurationService();
      final service = Obd2Service(
        connectionType: ConnectionType.demo,
        configurationService: config,
      );
      final originalElm = service.elm327;

      await service.setConnectionType(ConnectionType.demo);

      expect(service.elm327, same(originalElm));
      expect(await config.getConnectionTypeName(), ConnectionType.demo.name);
    });

    test('scanForPeripherals toggles scanning state after success and failure',
        () async {
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final fakeElm = _FakeElm327();
      service.elm327 = fakeElm;

      final states = <bool>[];
      final sub = service.isScanningPublisher.listen(states.add);

      await service.scanForPeripherals();
      fakeElm.throwOnScan = true;
      await expectLater(service.scanForPeripherals(), throwsException);
      await pumpEventQueue();

      expect(states, [true, false, true, false]);
      expect(service.isScanning, isFalse);

      await sub.cancel();
    });

    test(
        'connectToPeripheral publishes selected peripheral and delegates connection',
        () async {
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final fakeElm = _FakeElm327();
      service.elm327 = fakeElm;
      final peripheral = Object();
      final emitted = <Object?>[];
      final sub = service.connectedPeripheralPublisher.listen(emitted.add);

      await service.connectToPeripheral(peripheral: peripheral, timeout: 1);

      expect(service.connectedPeripheral, same(peripheral));
      expect(fakeElm.connectedPeripheral, same(peripheral));
      expect(emitted, contains(same(peripheral)));

      await sub.cancel();
    });
  });

  group('Obd2Service requests and errors', () {
    test('requestPID returns DTC scan results for mode 03', () async {
      await Commands.ensureInitialized();
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final fakeElm = _FakeElm327()
        ..dtcResponse = {
          EcuId.engine: [
            TroubleCodeMetadata(
              code: 'P0300',
              title: 'Random Misfire',
              description: 'Random/multiple cylinder misfire detected',
              severity: 'Critical',
              causes: [],
              remedies: [],
            ),
          ],
        };
      service.elm327 = fakeElm;

      final result = await service.requestPID(Commands.allCommands['03']!);

      final decoded = result[Commands.allCommands['03']!]!;
      expect(decoded.troubleCodesByEcu, contains(EcuId.engine));
      expect(decoded.troubleCodes!.single.code, 'P0300');
    });

    test('requestPID handles protocol and payload edge cases', () async {
      await Commands.ensureInitialized();
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final fakeElm = _FakeElm327();
      service.elm327 = fakeElm;
      final rpm = Commands.allCommands['010C']!;

      expect(await service.requestPID(rpm), isEmpty);

      fakeElm.canProtocol = CanProtocol(ObdProtocol.protocol6);
      fakeElm.commandResponse = const ['NO DATA'];
      expect(await service.requestPID(rpm), isEmpty);

      fakeElm.commandResponse = const ['7E8 04 41 0C 0C 80'];
      final decoded = await service.requestPID(rpm);
      expect(decoded[rpm]!.measurementResult!.value, 800);

      final vin = Commands.allCommands['0902']!;
      fakeElm.commandResponse = const [
        '7E8 10 14 49 02 01 31 4E 34',
        '7E8 21 41 4C 33 41 50 37 44',
        '7E8 22 43 31 39 39 35 38 33',
      ];
      expect(await service.requestPID(vin), isNotEmpty);
    });

    test('wraps connection, command, scan, and clear failures', () async {
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final fakeElm = _FakeElm327();
      service.elm327 = fakeElm;

      fakeElm.throwOnConnect = true;
      await expectLater(
        service.startConnection(),
        throwsA(isA<ObdServiceException>().having(
          (e) => e.type,
          'type',
          ObdServiceErrorType.adapterConnectionFailed,
        )),
      );

      fakeElm.throwOnCommand = true;
      await expectLater(
        service.sendCommand('0100'),
        throwsA(isA<ObdServiceException>().having(
          (e) => e.type,
          'type',
          ObdServiceErrorType.commandFailed,
        )),
      );

      fakeElm.throwOnDtcScan = true;
      await expectLater(
        service.scanForTroubleCodes(),
        throwsA(isA<ObdServiceException>().having(
          (e) => e.type,
          'type',
          ObdServiceErrorType.scanFailed,
        )),
      );

      fakeElm.throwOnClear = true;
      await expectLater(
        service.clearTroubleCodes(),
        throwsA(isA<ObdServiceException>().having(
          (e) => e.type,
          'type',
          ObdServiceErrorType.clearFailed,
        )),
      );
    });

    test('connectionStateChanged clears connected peripheral on disconnect',
        () async {
      final service = Obd2Service(connectionType: ConnectionType.demo);
      final emitted = <Object?>[];
      final sub = service.connectedPeripheralPublisher.listen(emitted.add);

      service.connectedPeripheral = Object();
      service.connectionStateChanged(ConnectionState.connectedToAdapter);
      service.connectionStateChanged(ConnectionState.disconnected);
      await pumpEventQueue();

      expect(service.connectionState, ConnectionState.disconnected);
      expect(service.connectedPeripheral, isNull);
      expect(emitted, contains(null));

      await sub.cancel();
    });
  });
}
