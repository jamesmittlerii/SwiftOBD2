import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

class FakeComm implements CommProtocol {
  @override
  ObdServiceDelegate? obdDelegate;

  final _stateController = StreamController<ConnectionState>.broadcast();

  @override
  Stream<ConnectionState> get connectionStatePublisher => _stateController.stream;

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
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

void main() {
  group('ELM327 Tests', () {
    test('setupVehicle detects protocol6', () async {
      final sut = Elm327(FakeComm());
      final info = await sut.setupVehicle(preferredProtocol: null, querySupportedPIDs: false);
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
      expect(supported.any((c) => c.properties.command == "010C"), isTrue); // RPM
    });
  });
}
