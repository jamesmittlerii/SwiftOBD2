import 'dart:async';
import '../comm_protocol.dart';

abstract class BaseCommProtocol implements CommProtocol {
  final _connectionStateController = StreamController<ConnectionState>.broadcast();
  
  @override
  Stream<ConnectionState> get connectionStatePublisher => _connectionStateController.stream;

  @override
  ObdServiceDelegate? obdDelegate;

  Completer<List<String>>? _messageCompleter;
  final StringBuffer _receiveBuffer = StringBuffer();

  /// Serial queue for commands to prevent concurrent access issues.
  Future<void> _lock = Future.value();

  void setConnectionState(ConnectionState state) {
    _connectionStateController.add(state);
    obdDelegate?.connectionStateChanged(state);
  }

  void failPendingMessage(Exception error) {
    if (_messageCompleter != null && !_messageCompleter!.isCompleted) {
      _messageCompleter!.completeError(error);
      _messageCompleter = null;
    }
    _receiveBuffer.clear();
  }

  void processStringData(String data) {
    _receiveBuffer.write(data);

    if (_receiveBuffer.toString().contains(">")) {
      final fullResponse = _receiveBuffer.toString();
      _receiveBuffer.clear();

      final parsed = _parseResponse(fullResponse);
      if (_messageCompleter != null && !_messageCompleter!.isCompleted) {
        _messageCompleter!.complete(parsed);
      }
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

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    final completer = Completer<List<String>>();
    final previousLock = _lock;
    final newLock = Completer<void>();
    _lock = newLock.future;

    try {
      await previousLock;
      await ensureConnected();
      
      final result = await _executeCommand(message, retries: retries);
      completer.complete(result);
    } catch (e) {
      completer.completeError(e);
    } finally {
      newLock.complete();
    }

    return completer.future;
  }

  Future<List<String>> _executeCommand(String message, {int retries = 3}) async {
    Exception? lastError;
    for (int i = 0; i < retries; i++) {
      _messageCompleter = Completer<List<String>>();
      try {
        await writeCommand("$message\r");

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

  Future<void> ensureConnected();

  Future<void> writeCommand(String command);
}
