import 'dart:async';
import 'dart:math';

import '../comm_protocol.dart';

class MockManager implements CommProtocol {
  final _stateController = StreamController<ConnectionState>.broadcast();
  final _random = Random();

  @override
  Stream<ConnectionState> get connectionStatePublisher => _stateController.stream;

  @override
  ObdServiceDelegate? obdDelegate;

  bool _connected = false;
  bool _headerOn = true;
  bool _echoOn = false;
  DateTime? _sessionStart;
  DateTime? _lastTick;
  double _elapsedSeconds = 0;

  @override
  Future<void> connectAsync({required double timeout, Object? peripheral}) async {
    _connected = true;
    _emit(ConnectionState.connectedToAdapter);
  }

  @override
  void disconnectPeripheral() {
    _connected = false;
    _emit(ConnectionState.disconnected);
  }

  @override
  Future<void> scanForPeripherals() async {
    // No-op in mock mode.
  }

  @override
  Future<List<String>> sendCommand(String message, {int retries = 3}) async {
    if (!_connected) {
      throw Exception("Mock adapter not connected");
    }

    if (message.startsWith("AT")) {
      final action = message.substring(2);
      if (action == "H1") {
        _headerOn = true;
        return _reply("OK", message);
      }
      if (action == "H0") {
        _headerOn = false;
        return _reply("OK", message);
      }
      if (action == "E1") {
        _echoOn = true;
        return _reply("OK", message);
      }
      if (action == "E0") {
        _echoOn = false;
        return _reply("OK", message);
      }
      if (action == "Z") return ["ELM327 v1.5"];
      if (action == "DPN") return ["06"];
      if (action == "RV") return _reply("13.8", message);
      return _reply("OK", message);
    }

    switch (message) {
      case "0100":
        return [_frame("06 41 00 FF FF FF FF")];
      case "0120":
        // Mirrors Swift mock: full support bitmap for 0x21-0x40 range.
        return [_frame("06 41 20 FF FF FF FF")];
      case "0140":
        // Mirrors Swift mock intent: support broad 0x41-0x60 coverage.
        return [_frame("06 41 40 FF FF FF FE")];
      case "010C":
        return [_frame("04 41 0C ${_rpmBytes()}")];
      case "0101":
        return [_frame("06 41 01 ${_milBytes()}")];
      case "0103":
        return [_frame("04 41 03 ${_fuelStatusBytes()}")];
      case "010D":
        return [_frame("03 41 0D ${_speedByte()}")];
      case "0105":
        return [_frame("03 41 05 ${_coolantByte()}")];
      case "010F":
        return [_frame("03 41 0F ${_intakeTempByte()}")];
      case "0142":
        return [_frame("04 41 42 ${_voltageBytes()}")];
      case "0111":
        return [_frame("03 41 11 ${_throttleByte()}")];
      case "0104":
        return [_frame("03 41 04 ${_engineLoadByte()}")];
      case "0143":
        return [_frame("04 41 43 ${_absoluteLoadBytes()}")];
      case "010B":
        return [_frame("03 41 0B ${_intakePressureByte()}")];
      case "0110":
        return [_frame("04 41 10 ${_mafBytes()}")];
      case "010E":
        return [_frame("03 41 0E ${_timingAdvanceByte()}")];
      case "0146":
        return [_frame("03 41 46 ${_ambientTempByte()}")];
      case "012F":
        return [_frame("03 41 2F ${_fuelLevelByte()}")];
      case "0133":
        return [_frame("03 41 33 ${_baroPressureByte()}")];
      case "010A":
      case "0159":
      case "0122":
      case "0123":
        return [_frame("03 41 ${message.substring(2)} ${_fuelPressureByte()}")];
      case "0106":
      case "0107":
      case "0108":
      case "0109":
        return [_frame("03 41 ${message.substring(2)} ${_fuelTrimByte(message)}")];
      case "0114":
      case "0115":
      case "0118":
      case "0119":
        return [_frame("04 41 ${message.substring(2)} ${_o2Bytes(message)}")];
      case "013C":
      case "013D":
      case "013E":
      case "013F":
        return [_frame("04 41 ${message.substring(2)} ${_catTempBytes(message)}")];
      case "0144":
        return [_frame("04 41 44 ${_lambdaBytes()}")];
      case "0145":
      case "0147":
      case "0148":
      case "0149":
      case "014A":
      case "014B":
      case "014C":
      case "015A":
      case "015B":
        return [_frame("03 41 ${message.substring(2)} ${_relativeThrottleByte(message)}")];
      case "011F":
        return [_frame("04 41 1F ${_runtimeBytes()}")];
      case "0121":
      case "0131":
        return [_frame("04 41 ${message.substring(2)} ${_distanceBytes()}")];
      case "012E":
        return [_frame("03 41 2E ${_evapPurgeByte()}")];
      case "012C":
        return [_frame("03 41 2C ${_egrByte()}")];
      case "0902":
        return [
          _frame("10 14 49 02 01 31 4E 34"),
          _frame("21 41 4C 33 41 50 37 44"),
          _frame("22 43 31 39 39 35 38 33"),
        ];
      case "03":
        return [
          _frame("10 10 43 07 03 00 01 70"),
          _frame("21 01 01 01 04 02 07 04"),
          _frame("22 11 04 20 00 00 00 00"),
        ];
      case "04":
        return _reply("44", message);
      default:
        return _reply("NO DATA", message);
    }
  }

  List<String> _reply(String payload, String command) {
    if (_echoOn) {
      return [command, payload];
    }
    return [payload];
  }

  String _frame(String body) {
    if (_headerOn) {
      return "7E8 $body";
    }
    return body;
  }

  void _tick() {
    final now = DateTime.now();
    _sessionStart ??= now;
    _lastTick ??= now;
    final dt = now.difference(_lastTick!).inMilliseconds / 1000.0;
    _lastTick = now;
    _elapsedSeconds += dt;
  }

  double _speedKmh() {
    _tick();
    const ramp = 15.0;
    if (_elapsedSeconds < ramp) {
      return (_elapsedSeconds / ramp) * 20.0;
    }
    return 45.0 + 25.0 * sin((_elapsedSeconds - ramp) / 30.0 * pi * 2.0);
  }

  String _speedByte() {
    final v = _speedKmh().clamp(0.0, 255.0).round();
    return v.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  String _rpmBytes() {
    final speed = _speedKmh();
    final rpm = speed <= 0.5
        ? 800.0
        : speed < 20.0
            ? 800.0 + 360.0 * speed
            : speed < 50.0
                ? 1500.0 + (6500.0 / 30.0) * (speed - 20.0)
                : 1800.0 + 310.0 * (speed - 50.0);
    final raw = (rpm.clamp(800.0, 8000.0).round()) * 4;
    final a = ((raw >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = (raw & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    return "$a $b";
  }

  String _milBytes() {
    _tick();
    final stages = (_elapsedSeconds.clamp(0.0, 120.0) / 12.0).floor();
    // A0: MIL on + 7 DTCs
    const a0 = 0x87;

    // A: Misfire/Fuel/Comprehensive readiness bits (1 = not ready)
    var a = 0x70;
    // B: gasoline monitor support bits
    const b = 0xEF; // catalyst/heated/evap/secondary-air/o2/o2-heater/egr
    // C: readiness bits for supported extended monitors (1 = not ready)
    var c = 0xEF;

    if (stages >= 1) a &= ~0x40; // Comprehensive
    if (stages >= 2) a &= ~0x20; // Fuel
    if (stages >= 3) a &= ~0x10; // Misfire
    if (stages >= 4) c &= ~0x40; // O2 Heater
    if (stages >= 5) c &= ~0x20; // O2 Sensor
    if (stages >= 6) c &= ~0x01; // Catalyst
    if (stages >= 7) c &= ~0x04; // Evap
    if (stages >= 8) c &= ~0x80; // EGR/VVT
    if (stages >= 9) c &= ~0x08; // Secondary Air
    if (stages >= 10) c &= ~0x02; // Heated Catalyst

    return "${_hexByte(a0)} ${_hexByte(a)} ${_hexByte(b)} ${_hexByte(c)}";
  }

  String _fuelStatusBytes() {
    _tick();
    final coolantC = ((_elapsedSeconds / 60.0).clamp(0.0, 1.0) * 100.0);
    final throttle = int.parse(_throttleByte(), radix: 16) * 100.0 / 255.0;
    int code;
    if (coolantC < 60.0) {
      code = 1; // cold open loop
    } else if (throttle < 3.0) {
      code = 3; // load/fuel cut open loop
    } else {
      code = 2; // closed loop
    }
    // FuelStatusDecoder expects one-hot bitset; code = 8 - index.
    final oneHotByCode = <int, int>{
      1: 0x01,
      2: 0x02,
      3: 0x04,
      4: 0x08,
      5: 0x10,
    };
    final oneHot = oneHotByCode[code] ?? 0x00;
    return "${_hexByte(oneHot)} ${_hexByte(oneHot)}";
  }

  String _coolantByte() {
    _tick();
    final temp = ((_elapsedSeconds / 60.0).clamp(0.0, 1.0) * 100.0).round();
    final raw = (temp + 40).clamp(0, 255);
    return raw.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  String _intakeTempByte() {
    _tick();
    final temp = ((_elapsedSeconds / 60.0).clamp(0.0, 1.0) * 70.0).round();
    final raw = (temp + 40).clamp(0, 255);
    return raw.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  String _ambientTempByte() => _hexByte(40 + 10 * sin(_elapsedSeconds * 0.03));

  String _throttleByte() {
    final speed = _speedKmh();
    final value = ((0.2 + ((speed / 120.0).clamp(0.0, 1.0)) + (_random.nextDouble() * 0.05))
            .clamp(0.0, 1.0) *
        255.0)
        .round();
    return value.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  String _engineLoadByte() {
    final speed = _speedKmh();
    final rpm = _rpmFromSpeed(speed);
    final rpmN = ((rpm - 800.0) / (8000.0 - 800.0)).clamp(0.0, 1.0);
    final load = (0.1 + 0.8 * rpmN + sin(_elapsedSeconds * 0.2) * 0.03).clamp(0.0, 1.0);
    return _hexByte(load * 255.0);
  }

  String _absoluteLoadBytes() {
    final speed = _speedKmh();
    final rpm = _rpmFromSpeed(speed);
    final rpmN = ((rpm - 800.0) / (8000.0 - 800.0)).clamp(0.0, 1.0);
    final load = (rpmN * 100.0).clamp(0.0, 100.0);
    final raw = (load / 100.0 * 65535.0).round();
    return "${_hexByte((raw >> 8) & 0xFF)} ${_hexByte(raw & 0xFF)}";
  }

  String _intakePressureByte() {
    final speed = _speedKmh();
    final rpm = _rpmFromSpeed(speed);
    final rpmN = ((rpm - 800.0) / (8000.0 - 800.0)).clamp(0.0, 1.0);
    final kpa = (25.0 + rpmN * 70.0 + sin(_elapsedSeconds * 0.17) * 2.0).clamp(20.0, 100.0);
    return _hexByte(kpa);
  }

  String _mafBytes() {
    final speed = _speedKmh();
    final rpm = _rpmFromSpeed(speed);
    final rpmN = ((rpm - 800.0) / (8000.0 - 8000.0 + 8000.0 - 800.0)).clamp(0.0, 1.0);
    final maf = (2.0 + rpmN * 118.0).clamp(2.0, 200.0);
    final raw = (maf * 100.0).round();
    return "${_hexByte((raw >> 8) & 0xFF)} ${_hexByte(raw & 0xFF)}";
  }

  String _timingAdvanceByte() {
    final speed = _speedKmh();
    final rpm = _rpmFromSpeed(speed);
    final rpmN = ((rpm - 800.0) / (8000.0 - 800.0)).clamp(0.0, 1.0);
    final advance = (10.0 + rpmN * 25.0).clamp(2.0, 45.0);
    return _hexByte((advance * 2.0) + 128.0);
  }

  String _baroPressureByte() => _hexByte((101.0 + sin(_elapsedSeconds * 0.01)).clamp(95.0, 105.0));

  String _fuelPressureByte() => _hexByte((400.0 / 3.0).clamp(0.0, 255.0));

  String _fuelTrimByte(String command) {
    final base = command.endsWith("6") || command.endsWith("8") ? 0.05 : 0.02;
    final centered = 128 + ((sin(_elapsedSeconds * 0.2) * base) * 255.0);
    return _hexByte(centered);
  }

  String _o2Bytes(String command) {
    final seed = int.parse(command.substring(2), radix: 16).toDouble();
    final v = (0.5 + sin((_elapsedSeconds + seed) * 0.4) * 0.25).clamp(0.1, 0.9);
    final a = ((v / 1.275) * 255.0).round();
    return "${_hexByte(a)} 80";
  }

  String _catTempBytes(String command) {
    final seed = int.parse(command.substring(2), radix: 16).toDouble();
    final temp = (300.0 + 250.0 * (0.5 + 0.5 * sin((_elapsedSeconds + seed) * 0.1))).clamp(200.0, 900.0);
    final raw = ((temp + 40.0) * 10.0).round();
    return "${_hexByte((raw >> 8) & 0xFF)} ${_hexByte(raw & 0xFF)}";
  }

  String _lambdaBytes() {
    final lambda = (1.0 + sin(_elapsedSeconds * 0.2) * 0.03).clamp(0.9, 1.1);
    final raw = (lambda * 32768.0).round();
    return "${_hexByte((raw >> 8) & 0xFF)} ${_hexByte(raw & 0xFF)}";
  }

  String _relativeThrottleByte(String command) {
    final speed = _speedKmh();
    final base = (0.2 + ((speed / 120.0).clamp(0.0, 1.0))).clamp(0.0, 1.0);
    final seed = int.parse(command.substring(2), radix: 16).toDouble();
    return _hexByte(((base + sin((_elapsedSeconds + seed) * 0.05) * 0.02).clamp(0.0, 1.0)) * 255.0);
  }

  String _runtimeBytes() {
    _tick();
    final seconds = _elapsedSeconds.round().clamp(0, 65535);
    return "${_hexByte((seconds >> 8) & 0xFF)} ${_hexByte(seconds & 0xFF)}";
  }

  String _distanceBytes() {
    final km = (_speedKmh() * (_elapsedSeconds / 3600.0)).round().clamp(0, 65535);
    return "${_hexByte((km >> 8) & 0xFF)} ${_hexByte(km & 0xFF)}";
  }

  String _evapPurgeByte() => _hexByte((0.2 + 0.2 * sin(_elapsedSeconds * 0.2)) * 255.0);

  String _egrByte() => _hexByte((0.2 + 0.2 * sin(_elapsedSeconds * 0.3)) * 255.0);

  String _voltageBytes() {
    _tick();
    final volts = (13.6 + sin(_elapsedSeconds * 0.05) * 0.15).clamp(12.2, 14.6);
    final raw = (volts * 1000.0).round();
    return "${_hexByte((raw >> 8) & 0xFF)} ${_hexByte(raw & 0xFF)}";
  }

  double _rpmFromSpeed(double speed) {
    return speed <= 0.5
        ? 800.0
        : speed < 20.0
            ? 800.0 + 360.0 * speed
            : speed < 50.0
                ? 1500.0 + (6500.0 / 30.0) * (speed - 20.0)
                : 1800.0 + 310.0 * (speed - 50.0);
  }

  String _hexByte(num value) => value.round().clamp(0, 255).toRadixString(16).padLeft(2, '0').toUpperCase();

  String _fuelLevelByte() {
    _tick();
    final fuel = (90.0 - (_elapsedSeconds / 10.0)).clamp(0.0, 100.0);
    final raw = (fuel / 100.0 * 255.0).round().clamp(0, 255);
    return raw.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  void _emit(ConnectionState state) {
    _stateController.add(state);
    obdDelegate?.connectionStateChanged(state);
  }
}
