import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../comm_protocol.dart';
import 'base_comm_protocol.dart';

class BleManager extends BaseCommProtocol {
  final _connectedPeripheralController = StreamController<Object?>.broadcast();
  final _discoveredPeripheralsController = StreamController<List<Object>>.broadcast();
  final List<BluetoothDevice> _discoveredPeripherals = [];
  
  Stream<Object?> get connectedPeripheralPublisher => _connectedPeripheralController.stream;
  Stream<List<Object>> get discoveredPeripheralsPublisher => _discoveredPeripheralsController.stream;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription? _rxSubscription;
  StreamSubscription? _connectionStateSub;

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
    setConnectionState(ConnectionState.connecting);

    if (peripheral is BluetoothDevice) {
      _device = peripheral;
      _connectedPeripheralController.add(_device);
    } else {
      // Find a device if none passed
      _device = await _scanForFirstObdDevice(timeout: timeout);
      if (_device == null) {
        setConnectionState(ConnectionState.error);
        throw Exception("No OBD BLE adapter found.");
      }
      _connectedPeripheralController.add(_device);
    }

    try {
      await _device!.connect(
        license: License.free,
        timeout: Duration(milliseconds: (timeout * 1000).toInt()),
      );
      
      _connectionStateSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          setConnectionState(ConnectionState.disconnected);
        }
      });

      await _setupCharacteristics();

      setConnectionState(ConnectionState.connectedToAdapter);
    } catch (e) {
      setConnectionState(ConnectionState.error);
      throw Exception("Failed to connect to adapter: $e");
    }
  }

  @override
  void disconnectPeripheral() {
    _rxSubscription?.cancel();
    _connectionStateSub?.cancel();
    _device?.disconnect();
    _device = null;
    _connectedPeripheralController.add(null);
    _writeCharacteristic = null;
    _readCharacteristic = null;
    failPendingMessage(Exception("Disconnected"));
    setConnectionState(ConnectionState.disconnected);
  }

  @override
  Future<void> ensureConnected() async {
    if (_writeCharacteristic == null || _device == null) {
      throw Exception("BLE device or write characteristic not connected.");
    }
  }

  @override
  Future<void> writeCommand(String command) async {
    final commandData = ascii.encode(command);
    if (_writeCharacteristic!.properties.writeWithoutResponse) {
      await _writeCharacteristic!.write(commandData, withoutResponse: true);
    } else {
      await _writeCharacteristic!.write(commandData, withoutResponse: false);
    }
  }

  @override
  Future<void> scanForPeripherals() async {
    _discoveredPeripherals.clear();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final exists = _discoveredPeripherals.any((d) => d.remoteId == r.device.remoteId);
        if (!exists) {
          _discoveredPeripherals.add(r.device);
        }
      }
      _discoveredPeripheralsController.add(List<Object>.from(_discoveredPeripherals));
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    await FlutterBluePlus.stopScan();
    await sub.cancel();
  }

  Future<BluetoothDevice?> _scanForFirstObdDevice({required double timeout}) async {
    final completer = Completer<BluetoothDevice?>();
    
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // Simple heuristic: just return the first device with OBD or V-LINK in its name
        final name = r.device.platformName.toLowerCase();
        if (name.contains("obd") || name.contains("v-link") || name.contains("ble") || name.contains("ios")) {
          completer.complete(r.device);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: Duration(milliseconds: (timeout * 1000).toInt()));

    try {
      final device = await completer.future.timeout(Duration(milliseconds: (timeout * 1000).toInt()));
      subscription.cancel();
      await FlutterBluePlus.stopScan();
      return device;
    } catch (_) {
      subscription.cancel();
      await FlutterBluePlus.stopScan();
      return null;
    }
  }

  Future<void> _setupCharacteristics() async {
    if (_device == null) return;
    
    List<BluetoothService> services = await _device!.discoverServices();
    
    for (BluetoothService service in services) {
      final uuidStr = service.uuid.toString().toUpperCase();
      // Check common OBD BLE Service UUIDs
      if (uuidStr.contains("FFE0") || uuidStr.contains("FFF0") || uuidStr.contains("18F0") || uuidStr.contains("FFC0") || uuidStr.contains("6E400001")) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            _writeCharacteristic = c;
          }
          if (c.properties.notify || c.properties.indicate) {
            _readCharacteristic = c;
          }
        }
        break; // found the service
      }
    }

    // Fallback: Just find any characteristic that can write, and any that can notify
    if (_writeCharacteristic == null || _readCharacteristic == null) {
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic c in service.characteristics) {
          if (_writeCharacteristic == null && (c.properties.write || c.properties.writeWithoutResponse)) {
            _writeCharacteristic = c;
          }
          if (_readCharacteristic == null && (c.properties.notify || c.properties.indicate)) {
            _readCharacteristic = c;
          }
        }
      }
    }

    if (_writeCharacteristic == null || _readCharacteristic == null) {
      throw Exception("Could not find read/write characteristics on the device.");
    }

    // Subscribe to notifications
    await _readCharacteristic!.setNotifyValue(true);
    _rxSubscription = _readCharacteristic!.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        _processReceivedData(value);
      }
    });
  }

  void _processReceivedData(List<int> data) {
    try {
      final str = ascii.decode(data);
      processStringData(str);
    } catch (e) {
      // Decode error or similar, log it but don't crash
      // print("Error decoding BLE data: $e");
    }
  }
}
