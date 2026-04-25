import 'dart:async';

import '../comm_protocol.dart';

/// In-memory transport used only for `ConnectionType.demo`.
/// Keeps the connection lifecycle deterministic and never touches platform BLE APIs.
class DemoManager implements CommProtocol {
  final _connectionStateController = StreamController<ConnectionState>.broadcast();

  @override
  Stream<ConnectionState> get connectionStatePublisher => _connectionStateController.stream;

  @override
  ObdServiceDelegate? obdDelegate;

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
    _setConnectionState(ConnectionState.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _setConnectionState(ConnectionState.connectedToAdapter);
  }

  @override
  void disconnectPeripheral() {
    _setConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    // Demo responses are synthesized in Obd2Service and should not route here.
    // Return an ELM-style prompt to keep callers robust if invoked accidentally.
    return const ["OK", ">"];
  }

  @override
  Future<void> scanForPeripherals() async {
    // No-op for demo.
  }

  void _setConnectionState(ConnectionState state) {
    _connectionStateController.add(state);
    obdDelegate?.connectionStateChanged(state);
  }
}
