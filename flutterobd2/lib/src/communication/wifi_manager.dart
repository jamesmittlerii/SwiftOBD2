import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../comm_protocol.dart';

class WifiManager implements CommProtocol {
  final String host;
  final int port;
  final _connectionStateController = StreamController<ConnectionState>.broadcast();
  
  Socket? _socket;
  StreamSubscription? _socketSubscription;

  Completer<List<String>>? _messageCompleter;
  final StringBuffer _receiveBuffer = StringBuffer();

  WifiManager({this.host = "192.168.0.10", this.port = 35000});

  @override
  Stream<ConnectionState> get connectionStatePublisher => _connectionStateController.stream;

  @override
  ObdServiceDelegate? obdDelegate;

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
    _setConnectionState(ConnectionState.connecting);
    
    try {
      _socket = await Socket.connect(host, port, timeout: Duration(milliseconds: (timeout * 1000).toInt()));
      
      _socketSubscription = _socket!.listen(
        _onDataReceived,
        onError: _onError,
        onDone: _onDone,
      );

      _setConnectionState(ConnectionState.connectedToAdapter);
    } catch (e) {
      _setConnectionState(ConnectionState.error);
      throw Exception("WiFi connection failed: $e");
    }
  }

  @override
  void disconnectPeripheral() {
    _socketSubscription?.cancel();
    _socket?.destroy();
    _socket = null;
    _failPendingMessage(Exception("Disconnected"));
    _setConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    if (_socket == null) {
      throw Exception("Socket not connected");
    }

    if (_messageCompleter != null) {
      throw Exception("A command is already in progress.");
    }

    Exception? lastError;
    for (int i = 0; i < retries; i++) {
      _messageCompleter = Completer<List<String>>();
      try {
        _socket!.write("$message\r");

        final response = await _messageCompleter!.future.timeout(const Duration(seconds: 10));
        _messageCompleter = null;
        return response;
      } on TimeoutException {
        _messageCompleter = null;
        lastError = Exception("Timeout waiting for response for command: $message");
      } catch (e) {
        _messageCompleter = null;
        lastError = Exception("Error sending command $message: $e");
      }
      
      if (i < retries - 1) await Future.delayed(const Duration(milliseconds: 250));
    }

    throw lastError ?? Exception("Failed to send command after $retries retries.");
  }

  @override
  Future<void> scanForPeripherals() async {
    // Usually no-op for WiFi OBD2 adapters as they have static IP/port
  }

  void _onDataReceived(List<int> data) {
    try {
      final str = ascii.decode(data, allowInvalid: true);
      _receiveBuffer.write(str);

      if (_receiveBuffer.toString().contains(">")) {
        final fullResponse = _receiveBuffer.toString();
        _receiveBuffer.clear();

        final parsed = _parseResponse(fullResponse);
        if (_messageCompleter != null && !_messageCompleter!.isCompleted) {
          _messageCompleter!.complete(parsed);
        }
      }
    } catch (e) {
      // Decode error
    }
  }

  List<String> _parseResponse(String response) {
    return response
        .replaceAll(">", "")
        .split('\n')
        .map((s) => s.replaceAll('\r', '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _onError(Object error) {
    _failPendingMessage(Exception("Socket error: $error"));
    _setConnectionState(ConnectionState.error);
    disconnectPeripheral();
  }

  void _onDone() {
    _failPendingMessage(Exception("Socket closed by remote"));
    _setConnectionState(ConnectionState.disconnected);
    disconnectPeripheral();
  }

  void _setConnectionState(ConnectionState state) {
    _connectionStateController.add(state);
    obdDelegate?.connectionStateChanged(state);
  }

  void _failPendingMessage(Exception error) {
    if (_messageCompleter != null && !_messageCompleter!.isCompleted) {
      _messageCompleter!.completeError(error);
      _messageCompleter = null;
    }
    _receiveBuffer.clear();
  }
}
