import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../comm_protocol.dart';
import 'base_comm_protocol.dart';

class WifiManager extends BaseCommProtocol {
  final String host;
  final int port;
  
  Socket? _socket;
  StreamSubscription? _socketSubscription;

  WifiManager({this.host = "192.168.0.10", this.port = 35000});

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
    setConnectionState(ConnectionState.connecting);
    
    try {
      _socket = await Socket.connect(host, port, timeout: Duration(milliseconds: (timeout * 1000).toInt()));
      
      _socketSubscription = _socket!.listen(
        _onDataReceived,
        onError: _onError,
        onDone: _onDone,
      );

      setConnectionState(ConnectionState.connectedToAdapter);
    } catch (e) {
      setConnectionState(ConnectionState.error);
      throw Exception("WiFi connection failed: $e");
    }
  }

  @override
  void disconnectPeripheral() {
    _socketSubscription?.cancel();
    _socket?.destroy();
    _socket = null;
    failPendingMessage(Exception("Disconnected"));
    setConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<void> ensureConnected() async {
    if (_socket == null) {
      throw Exception("Socket not connected");
    }
  }

  @override
  Future<void> writeCommand(String command) async {
    _socket!.write(command);
  }

  @override
  Future<void> scanForPeripherals() async {
    // Usually no-op for WiFi OBD2 adapters as they have static IP/port
  }

  void _onDataReceived(List<int> data) {
    try {
      final str = ascii.decode(data, allowInvalid: true);
      processStringData(str);
    } catch (e) {
      // Decode error
    }
  }

  void _onError(Object error) {
    failPendingMessage(Exception("Socket error: $error"));
    setConnectionState(ConnectionState.error);
    disconnectPeripheral();
  }

  void _onDone() {
    failPendingMessage(Exception("Socket closed by remote"));
    setConnectionState(ConnectionState.disconnected);
    disconnectPeripheral();
  }
}
