import 'dart:async';

enum ConnectionState {
  disconnected,
  connecting,
  connectedToAdapter,
  connectedToVehicle,
  error;

  String get description {
    switch (this) {
      case ConnectionState.disconnected: return "Disconnected";
      case ConnectionState.connecting: return "Connecting";
      case ConnectionState.connectedToAdapter: return "Connected to Adapter";
      case ConnectionState.connectedToVehicle: return "Connected to Vehicle";
      case ConnectionState.error: return "Error";
    }
  }

  bool get isConnected => this == ConnectionState.connectedToAdapter || this == ConnectionState.connectedToVehicle;
}

abstract class ObdServiceDelegate {
  void connectionStateChanged(ConnectionState state);
}

abstract class CommProtocol {
  Stream<ConnectionState> get connectionStatePublisher;
  ObdServiceDelegate? obdDelegate;
  
  Future<void> connectAsync({required double timeout, Object? peripheral});
  void disconnectPeripheral();
  Future<List<String>> sendCommand(String message, {int retries = 3});
  Future<void> scanForPeripherals();
}
