import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

class FakeComm implements CommProtocol {
  @override
  ObdServiceDelegate? obdDelegate;

  final _stateController = StreamController<ConnectionState>.broadcast();

  @override
  Stream<ConnectionState> get connectionStatePublisher =>
      _stateController.stream;

  @override
  Future<void> connectAsync(
      {required double timeout, Object? peripheral}) async {
    _stateController.add(ConnectionState.connectedToAdapter);
  }

  @override
  void disconnectPeripheral() {
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Future<void> scanForPeripherals() async {}

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    switch (message) {
      case "ATSP0":
      case "ATE0":
      case "ATS0":
      case "ATL0":
      case "ATH1":
      case "ATAT1":
      case "ATAL":
      case "ATST64":
        return ["OK"];
      case "ATZ":
        return ["ELM327"];
      case "ATDPN":
        return ["A6"];
      case "0100":
        return ["7E8 06 41 00 BE 3F A8 13"];
      case "0902":
        return [
          "7E8 10 14 49 02 01 31 4E 34",
          "7E8 21 41 4C 33 41 50 37 44",
          "7E8 22 43 31 39 39 35 38 33",
        ];
      default:
        return ["NO DATA"];
    }
  }
}

class ScriptedComm implements CommProtocol {
  ScriptedComm(this.handler);

  final FutureOr<List<String>> Function(String message, int retries) handler;
  final sent = <String>[];
  final _stateController = StreamController<ConnectionState>.broadcast();

  @override
  ObdServiceDelegate? obdDelegate;

  @override
  Stream<ConnectionState> get connectionStatePublisher =>
      _stateController.stream;

  @override
  Future<void> connectAsync(
      {required double timeout, Object? peripheral}) async {
    _stateController.add(ConnectionState.connectedToAdapter);
  }

  @override
  void disconnectPeripheral() {
    _stateController.add(ConnectionState.disconnected);
  }

  @override
  Future<void> scanForPeripherals() async {}

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    sent.add(message);
    return handler(message, retries);
  }
}

void main() {
  group('ELM327 Tests', () {
    test('setupVehicle detects protocol6', () async {
      final sut = Elm327(FakeComm());
      final info = await sut.setupVehicle(
          preferredProtocol: null, querySupportedPIDs: false);
      expect(info.obdProtocol, ObdProtocol.protocol6);
    });

    test('adapterInitialization uses tolerant startup settings', () async {
      final sut = Elm327(FakeComm());
      await sut.adapterInitialization();
    });

    test('getSupportedPIDs returns values from 0100 bitmap', () async {
      final sut = Elm327(FakeComm());
      await sut.setupVehicle(preferredProtocol: null, querySupportedPIDs: true);
      final supported = await sut.getSupportedPIDs();
      expect(supported, isNotEmpty);
      expect(
          supported.any((c) => c.properties.command == "010C"), isTrue); // RPM
    });

    test('Elm327Error formats static and generated errors', () {
      expect(Elm327Error.noConnection.toString(), contains('No connection'));
      expect(
        Elm327Error.invalidResponse('bad frame').toString(),
        contains('bad frame'),
      );
      expect(
        Elm327Error.sendFailed(Exception('write')).toString(),
        contains('write'),
      );
    });

    test(
        'adapterInitialization throws a typed error when startup command fails',
        () async {
      final sut = Elm327(ScriptedComm((message, retries) {
        if (message == 'ATS0') return ['NO DATA'];
        if (message == 'ATZ') return ['ELM327'];
        return ['OK'];
      }));

      await expectLater(
        sut.adapterInitialization(),
        throwsA(same(Elm327Error.adapterInitializationFailed)),
      );
    });

    test('preferred protocol succeeds without automatic detection', () async {
      final comm = ScriptedComm((message, retries) {
        switch (message) {
          case '0100':
            return ['7E8 06 41 00 BE 3F A8 13'];
          case '0902':
            return ['7E8 04 49 02 31 32'];
          default:
            return ['OK'];
        }
      });
      final sut = Elm327(comm);

      final info = await sut.setupVehicle(
        preferredProtocol: ObdProtocol.protocol6,
        querySupportedPIDs: false,
      );

      expect(info.obdProtocol, ObdProtocol.protocol6);
      expect(comm.sent, isNot(contains('ATDPN')));
    });

    test(
        'falls back to manual protocol detection when automatic detection is invalid',
        () async {
      var first0100 = true;
      final comm = ScriptedComm((message, retries) {
        if (message == 'ATDPN') return ['?'];
        if (message == '0100') {
          if (first0100) {
            first0100 = false;
            return ['NO DATA'];
          }
          return ['7E8 06 41 00 BE 3F A8 13'];
        }
        if (message == '0902') return ['7E8 04 49 02 31 32'];
        return ['OK'];
      });
      final sut = Elm327(comm);

      final info = await sut.setupVehicle(querySupportedPIDs: false);

      expect(info.obdProtocol, isNot(ObdProtocol.none));
      expect(comm.sent, contains('ATDPN'));
      expect(
          comm.sent.any((m) => m.startsWith('ATSP') && m != 'ATSP0'), isTrue);
    });

    test('reports no protocol when automatic and manual detection fail',
        () async {
      final sut = Elm327(ScriptedComm((message, retries) {
        if (message == 'ATDPN') return ['?'];
        if (message == '0100') return ['NO DATA'];
        return ['OK'];
      }));

      await expectLater(
        sut.setupVehicle(querySupportedPIDs: false),
        throwsA(same(Elm327Error.noProtocolFound)),
      );
    });

    test('getStatus, trouble-code scan, and clear codes use command catalog',
        () async {
      await Commands.ensureInitialized();
      final comm = ScriptedComm((message, retries) {
        switch (message) {
          case '0101':
            return ['7E8 06 41 01 87 70 EF EF'];
          case '03':
            return ['7E8 06 43 01 01 00 00 00'];
          default:
            return ['OK'];
        }
      });
      final sut = Elm327(comm)
        ..canProtocol = CanProtocol(ObdProtocol.protocol6);

      expect(await sut.getStatus(), isNotNull);
      final dtcs = await sut.scanForTroubleCodes();
      expect(dtcs[EcuId.engine]!.single.code, 'P0100');
      await sut.clearTroubleCodes();
      if (Commands.allCommands.containsKey('04')) {
        expect(comm.sent, contains('04'));
      }
    });

    test('VIN and status return null when protocol or data is unavailable',
        () async {
      final sut = Elm327(ScriptedComm((message, retries) => ['NO DATA']));

      expect(await sut.requestVin(), isNull);
      expect(await sut.getStatus(), isNull);

      sut.canProtocol = CanProtocol(ObdProtocol.protocol6);
      expect(await sut.requestVin(), isNull);
      expect(await sut.getStatus(), isNull);
    });

    test('CanProtocol selects CAN or legacy parsers based on protocol', () {
      final can = CanProtocol(ObdProtocol.protocol6);
      final legacy = CanProtocol(ObdProtocol.protocol3);

      expect(can.parse(['7E8 03 41 0D 28']), isNotEmpty);
      expect(legacy.parse(['48 6B 10 41 0D 28']), isNotEmpty);
    });
  });
}
