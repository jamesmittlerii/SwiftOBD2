import 'dart:typed_data';
import 'utils.dart';
import 'data/trouble_codes.dart';
import 'data/codes.dart';
import 'parser.dart';

enum MeasurementUnit {
  metric("Metric"),
  imperial("Imperial");

  final String value;
  const MeasurementUnit(this.value);

  MeasurementUnit get next => this == MeasurementUnit.metric ? MeasurementUnit.imperial : MeasurementUnit.metric;
}

class Unit {
  final String symbol;
  const Unit(this.symbol);

  static const gallonsPerHour = Unit("gal/h");
  static const litersPerHour = Unit("L/h");
  static const percent = Unit("%");
  static const count = Unit("count");
  static const degrees = Unit("°");
  static const gramsPerSecond = Unit("g/s");
  static const poundsPerMinute = Unit("lb/min");
  static const none = Unit("");
  static const rpm = Unit("rpm");
  static const pascal = Unit("Pa");
  static const bar = Unit("bar");
  static const ppm = Unit("ppm");
  static const ratio = Unit("ratio");

  static const celsius = Unit("°C");
  static const fahrenheit = Unit("°F");
  
  static const kilometers = Unit("km");
  static const miles = Unit("mi");
  static const kilometersPerHour = Unit("km/h");
  static const milesPerHour = Unit("mph");

  static const kilopascals = Unit("kPa");
  static const poundsForcePerSquareInch = Unit("psi");

  static const millivolts = Unit("mV");
  static const volts = Unit("V");
  static const milliamperes = Unit("mA");
  static const amperes = Unit("A");

  static const milliseconds = Unit("ms");
  static const seconds = Unit("s");

  static const microohms = Unit("µΩ");
  static const ohms = Unit("Ω");
  static const kiloohms = Unit("kΩ");

  static const millihertz = Unit("mHz");
  static const hertz = Unit("Hz");
  static const kilohertz = Unit("kHz");
}

class MeasurementResult {
  final double value;
  final Unit unit;
  MeasurementResult(this.value, this.unit);
}

class StatusCodeMetadata {
  final String code;
  final String description;
  StatusCodeMetadata({required this.code, required this.description});
}

class TroubleCodeMetadata {
  final String code;
  final String title;
  final String description;
  final String severity;
  final List<String> causes;
  final List<String> remedies;

  TroubleCodeMetadata({
    required this.code,
    required this.title,
    required this.description,
    required this.severity,
    required this.causes,
    required this.remedies,
  });
}

class ReadinessMonitor {
  final String name;
  final bool supported;
  final bool ready;

  ReadinessMonitor({required this.name, required this.supported, required this.ready});
}

class Status {
  final bool milOn;
  final int dtcCount;
  final List<ReadinessMonitor> monitors;
  final String ignitionType;

  Status({required this.milOn, required this.dtcCount, required this.monitors, this.ignitionType = "Spark"});
}

class StatusTest {
  String name;
  bool supported;
  bool ready;

  StatusTest([this.name = "", this.supported = false, this.ready = false]);
}

class MonitorTest {
  int? tid;
  String? name;
  String? desc;
  MeasurementResult? value;
  double? min;
  double? max;

  bool get passed {
    if (value == null || min == null || max == null) return false;
    return value!.value >= min! && value!.value <= max!;
  }

  bool get isNull => tid == null || value == null || min == null || max == null;

  @override
  String toString() {
    return "${desc ?? ""} : ${value?.value ?? 0} [${passed ? "PASSED" : "FAILED"}]";
  }
}

class Monitor {
  Map<int, MonitorTest> tests = {};
}

class DecodeResult {
  final String? stringResult;
  final Status? statusResult;
  final List<StatusCodeMetadata?>? codeResult;
  final MeasurementResult? measurementResult;
  final List<TroubleCodeMetadata>? troubleCodes;
  final Monitor? measurementMonitor;
  final Map<EcuId, List<TroubleCodeMetadata>>? troubleCodesByEcu;

  DecodeResult({
    this.stringResult,
    this.statusResult,
    this.codeResult,
    this.measurementResult,
    this.troubleCodes,
    this.measurementMonitor,
    this.troubleCodesByEcu,
  });
}

abstract class Decoder {
  DecodeResult decode(Uint8List data, MeasurementUnit unit);
}

class Uas {
  final bool signed;
  final double scale;
  final Unit unit;
  final double offset;

  Uas({required this.signed, required this.scale, required this.unit, this.offset = 0.0});

  MeasurementResult decode(Uint8List bytes, [MeasurementUnit targetUnit = MeasurementUnit.metric]) {
    if (bytes.isEmpty) return MeasurementResult(0, unit);

    int bitWidth = bytes.length * 8;
    int intValue = 0;
    for (var byte in bytes) {
      intValue = (intValue << 8) | byte;
    }

    if (signed) {
      int signBit = 1 << (bitWidth - 1);
      if ((intValue & signBit) != 0) {
        intValue -= 1 << bitWidth;
      }
    }

    double baseValue = intValue * scale + offset;
    Unit baseUnit = this.unit;

    if (targetUnit == MeasurementUnit.imperial) {
      return _convertToImperial(baseValue, baseUnit);
    } else {
      return MeasurementResult(baseValue, baseUnit);
    }
  }

  MeasurementResult _convertToImperial(double value, Unit baseUnit) {
    if (baseUnit == Unit.celsius) {
      return MeasurementResult((value * 1.8) + 32.0, Unit.fahrenheit);
    } else if (baseUnit == Unit.kilometers) {
      return MeasurementResult(value * 0.621371, Unit.miles);
    } else if (baseUnit == Unit.kilometersPerHour) {
      return MeasurementResult(value * 0.621371, Unit.milesPerHour);
    } else if (baseUnit == Unit.kilopascals || baseUnit == Unit.bar) {
      double factor = baseUnit == Unit.bar ? 14.5038 : 0.145038;
      return MeasurementResult(value * factor, Unit.poundsForcePerSquareInch);
    } else if (baseUnit == Unit.gramsPerSecond) {
      return MeasurementResult(value * 0.132277, Unit.poundsPerMinute);
    } else if (baseUnit == Unit.litersPerHour) {
      return MeasurementResult(value * 0.264172, Unit.gallonsPerHour);
    }
    return MeasurementResult(value, baseUnit);
  }
}

final Map<int, Uas> uasIDS = {
  0x01: Uas(signed: false, scale: 1.0, unit: Unit.count),
  0x02: Uas(signed: false, scale: 0.1, unit: Unit.count),
  0x03: Uas(signed: false, scale: 0.01, unit: Unit.count),
  0x04: Uas(signed: false, scale: 0.001, unit: Unit.count),
  0x05: Uas(signed: false, scale: 0.0000305, unit: Unit.count),
  0x06: Uas(signed: false, scale: 0.000305, unit: Unit.count),
  0x07: Uas(signed: false, scale: 0.25, unit: Unit.rpm),
  0x09: Uas(signed: false, scale: 1, unit: Unit.kilometersPerHour),
  0x0A: Uas(signed: false, scale: 0.122, unit: Unit.millivolts),
  0x0B: Uas(signed: false, scale: 0.001, unit: Unit.volts),
  0x10: Uas(signed: false, scale: 1, unit: Unit.milliseconds),
  0x11: Uas(signed: false, scale: 100, unit: Unit.milliseconds),
  0x12: Uas(signed: false, scale: 1, unit: Unit.seconds),
  0x13: Uas(signed: false, scale: 1, unit: Unit.microohms),
  0x14: Uas(signed: false, scale: 1, unit: Unit.ohms),
  0x15: Uas(signed: false, scale: 1, unit: Unit.kiloohms),
  0x16: Uas(signed: false, scale: 0.1, unit: Unit.celsius, offset: -40.0),
  0x17: Uas(signed: false, scale: 0.01, unit: Unit.kilopascals),
  0x18: Uas(signed: false, scale: 0.0117, unit: Unit.kilopascals),
  0x19: Uas(signed: false, scale: 0.079, unit: Unit.kilopascals),
  0x1A: Uas(signed: false, scale: 1, unit: Unit.kilopascals),
  0x1B: Uas(signed: false, scale: 10, unit: Unit.kilopascals),
  0x1C: Uas(signed: false, scale: 0.01, unit: Unit.degrees),
  0x1D: Uas(signed: false, scale: 0.5, unit: Unit.degrees),
  0x1E: Uas(signed: false, scale: 0.0000305, unit: Unit.ratio),
  0x1F: Uas(signed: false, scale: 0.05, unit: Unit.ratio),
  0x20: Uas(signed: false, scale: 0.00390625, unit: Unit.ratio),
  0x21: Uas(signed: false, scale: 1, unit: Unit.millihertz),
  0x22: Uas(signed: false, scale: 1, unit: Unit.hertz),
  0x23: Uas(signed: false, scale: 1, unit: Unit.kilohertz),
  0x24: Uas(signed: false, scale: 1, unit: Unit.count),
  0x25: Uas(signed: false, scale: 1, unit: Unit.kilometers),
  0x27: Uas(signed: false, scale: 0.01, unit: Unit.gramsPerSecond),
  0x81: Uas(signed: true, scale: 1.0, unit: Unit.count),
  0x82: Uas(signed: true, scale: 0.1, unit: Unit.count),
  0x83: Uas(signed: true, scale: 0.01, unit: Unit.count),
  0x84: Uas(signed: true, scale: 0.001, unit: Unit.count),
  0x85: Uas(signed: true, scale: 0.0000305, unit: Unit.count),
  0x86: Uas(signed: true, scale: 0.000305, unit: Unit.count),
  0x87: Uas(signed: true, scale: 1, unit: Unit.ppm),
  0x8A: Uas(signed: true, scale: 0.122, unit: Unit.millivolts),
  0x8B: Uas(signed: true, scale: 0.001, unit: Unit.volts),
  0x8C: Uas(signed: true, scale: 0.01, unit: Unit.volts),
  0x8D: Uas(signed: true, scale: 0.00390625, unit: Unit.milliamperes),
  0x8E: Uas(signed: true, scale: 0.001, unit: Unit.amperes),
  0x90: Uas(signed: true, scale: 1, unit: Unit.milliseconds),
  0x96: Uas(signed: true, scale: 0.1, unit: Unit.celsius),
  0x99: Uas(signed: true, scale: 0.1, unit: Unit.kilopascals),
  0xFC: Uas(signed: true, scale: 0.01, unit: Unit.kilopascals),
  0xFD: Uas(signed: true, scale: 0.001, unit: Unit.kilopascals),
  0xFE: Uas(signed: true, scale: 0.25, unit: Unit.pascal),
};

// --- Decoders ---

class PercentDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    double value = data.isNotEmpty ? data[0].toDouble() : 0.0;
    value = value * 100.0 / 255.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.percent));
  }
}

class TemperatureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    double celsius = bytesToInt(data).toDouble() - 40.0;
    if (unit == MeasurementUnit.imperial) {
      double fahrenheit = (celsius * 9.0 / 5.0) + 32.0;
      return DecodeResult(measurementResult: MeasurementResult(fahrenheit, Unit.fahrenheit));
    } else {
      return DecodeResult(measurementResult: MeasurementResult(celsius, Unit.celsius));
    }
  }
}

class StringDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    String str = String.fromCharCodes(data);
    str = str.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return DecodeResult(stringResult: str);
  }
}

class UasDecoder implements Decoder {
  final int id;
  UasDecoder(this.id);

  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    var uas = uasIDS[id];
    if (uas == null) throw Exception("Invalid UAS ID");
    return DecodeResult(measurementResult: uas.decode(data, unit));
  }
}

class StatusDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 4) throw Exception("Invalid data for StatusDecoder");
    int milAndCount = data[0];
    bool milOn = (milAndCount & 0x80) != 0;
    int dtcCount = milAndCount & 0x7F;

    int a = data[1];
    int b = data[2];
    int c = data[3];

    bool isDiesel = (a & 0x08) != 0;
    List<ReadinessMonitor> monitors = [];

    if (isDiesel) {
      monitors = [
        ReadinessMonitor(name: "Misfire", supported: true, ready: (a & 0x10) == 0),
        ReadinessMonitor(name: "Fuel System", supported: true, ready: (a & 0x20) == 0),
        ReadinessMonitor(name: "Comprehensive Components", supported: true, ready: (a & 0x40) == 0),
        ReadinessMonitor(name: "NMHC catalyst", supported: (b & 0x01) != 0, ready: (c & 0x01) == 0),
        ReadinessMonitor(name: "HNOx/SCR Catalyst", supported: (b & 0x02) != 0, ready: (c & 0x02) == 0),
        ReadinessMonitor(name: "Boost pressure", supported: (b & 0x08) != 0, ready: (c & 0x08) == 0),
        ReadinessMonitor(name: "Exhaust gas", supported: (b & 0x20) != 0, ready: (c & 0x20) == 0),
        ReadinessMonitor(name: "PM filter", supported: (b & 0x40) != 0, ready: (c & 0x40) == 0),
        ReadinessMonitor(name: "EGR/VVT System", supported: (b & 0x80) != 0, ready: (c & 0x80) == 0),
      ];
    } else {
      monitors = [
        ReadinessMonitor(name: "Misfire", supported: true, ready: (a & 0x10) == 0),
        ReadinessMonitor(name: "Fuel System", supported: true, ready: (a & 0x20) == 0),
        ReadinessMonitor(name: "Comprehensive Components", supported: true, ready: (a & 0x40) == 0),
        ReadinessMonitor(name: "Catalyst", supported: (b & 0x01) != 0, ready: (c & 0x01) == 0),
        ReadinessMonitor(name: "Heated Catalyst", supported: (b & 0x02) != 0, ready: (c & 0x02) == 0),
        ReadinessMonitor(name: "Evaporative System", supported: (b & 0x04) != 0, ready: (c & 0x04) == 0),
        ReadinessMonitor(name: "Secondary Air System", supported: (b & 0x08) != 0, ready: (c & 0x08) == 0),
        ReadinessMonitor(name: "O₂ Sensor", supported: (b & 0x20) != 0, ready: (c & 0x20) == 0),
        ReadinessMonitor(name: "O₂ Heater", supported: (b & 0x40) != 0, ready: (c & 0x40) == 0),
        ReadinessMonitor(name: "EGR/VVT System", supported: (b & 0x80) != 0, ready: (c & 0x80) == 0),
      ];
    }
    return DecodeResult(statusResult: Status(milOn: milOn, dtcCount: dtcCount, monitors: monitors, ignitionType: isDiesel ? "Compression" : "Spark"));
  }
}

class DtcDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    List<TroubleCodeMetadata> codes = [];
    for (int i = 0; i < data.length - 1; i += 2) {
      var dtc = _parseDTC(Uint8List.fromList([data[i], data[i+1]]));
      if (dtc != null) {
        codes.add(dtc);
      }
    }
    return DecodeResult(troubleCodes: codes);
  }

  TroubleCodeMetadata? _parseDTC(Uint8List data) {
    if (data.length != 2 || (data[0] == 0x00 && data[1] == 0x00)) return null;
    int first = data[0];
    int second = data[1];

    List<String> prefix = ["P", "C", "B", "U"];
    String dtc = prefix[first >> 6];
    dtc += ((first >> 4) & 0x03).toString();
    int hexVal = ((first & 0x3F) << 8) | second;
    dtc += hexVal.toRadixString(16).padLeft(4, '0').substring(1).toUpperCase();

    if (troubleCodeDictionary.containsKey(dtc)) {
      return troubleCodeDictionary[dtc];
    } else {
      return TroubleCodeMetadata(
        code: dtc,
        title: "none",
        description: "No description available.",
        severity: "Moderate",
        causes: [],
        remedies: [],
      );
    }
  }
}

class SingleDtcDecoder extends DtcDecoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    var troubleCode = _parseDTC(data);
    return DecodeResult(troubleCodes: troubleCode != null ? [troubleCode] : []);
  }
}

class PercentCenteredDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    double value = data.isNotEmpty ? (data[0].toDouble() - 128.0) * 100.0 / 128.0 : 0.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.percent));
  }
}

class CurrentCenteredDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    var working = data;
    if (working.length >= 3 && working[0] == 0x41) {
      working = Uint8List.fromList(working.sublist(2));
    }
    if (working.isEmpty) {
      throw Exception("Invalid data for CurrentCenteredDecoder");
    }
    final value = (working[0].toDouble() - 128.0) * (2.0 / 128.0);
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.milliamperes));
  }
}

class SensorVoltageDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    double value = data.isNotEmpty ? data[0] / 200.0 : 0.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.volts));
  }
}

class FuelPressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    double value = data.isNotEmpty ? data[0] * 3.0 : 0.0;
    if (unit == MeasurementUnit.imperial) {
      value = value * 0.145038; // kPa to psi
      return DecodeResult(measurementResult: MeasurementResult(value, Unit.poundsForcePerSquareInch));
    }
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.kilopascals));
  }
}

class PressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final valueKpa = data.isNotEmpty ? data[0].toDouble() : 0.0;
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(valueKpa * 0.145038, Unit.poundsForcePerSquareInch),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(valueKpa, Unit.kilopascals));
  }
}

class TimingAdvanceDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final value = data.isNotEmpty ? (data[0] / 2.0) - 64.0 : -64.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.degrees));
  }
}

class SensorVoltageBigDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 4) {
      throw Exception("Invalid data for SensorVoltageBigDecoder");
    }
    final raw = bytesToInt(data.sublist(2, 4));
    final voltage = (raw * 8.0) / 65535.0;
    return DecodeResult(measurementResult: MeasurementResult(voltage, Unit.volts));
  }
}

class EvapPressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 2) {
      throw Exception("Invalid data for EvapPressureDecoder");
    }
    final combined = ((data[0] << 8) | data[1]);
    final signed = combined >= 0x8000 ? combined - 0x10000 : combined;
    final kpa = signed / 4.0;
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(kpa * 0.145038, Unit.poundsForcePerSquareInch),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(kpa, Unit.kilopascals));
  }
}

class AbsEvapPressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final valueKpa = bytesToInt(data) / 200.0;
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(valueKpa * 0.145038, Unit.poundsForcePerSquareInch),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(valueKpa, Unit.kilopascals));
  }
}

class EvapPressureAltDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final value = bytesToInt(data) - 32767.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.pascal));
  }
}

class InjectTimingDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 2) {
      throw Exception("Invalid data for InjectTimingDecoder");
    }
    final value = (bytesToInt(data) - 21000.0) / 10.0;
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.degrees));
  }
}

class FuelRateDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 2) {
      throw Exception("Invalid data for FuelRateDecoder");
    }
    final a = data[0];
    final b = data[1];
    final litersPerHour = (((a << 8) | b) * 0.05);
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(litersPerHour * 0.264172, Unit.gallonsPerHour),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(litersPerHour, Unit.litersPerHour));
  }
}

class GMEngineOilPressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.isEmpty) {
      throw Exception("Invalid data for GMEngineOilPressureDecoder");
    }
    final pressureKpa = (data[0] * 0.578) * 6.8947;
    final clamped = pressureKpa < 0 ? 0.0 : pressureKpa;
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(clamped * 0.145038, Unit.poundsForcePerSquareInch),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(clamped, Unit.kilopascals));
  }
}

class GMACPressureDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.isEmpty) {
      throw Exception("Invalid data for GMACPressureDecoder");
    }
    final pressureKpa = ((data[0] * 1.83) - 14.7) * 6.8947;
    final clamped = pressureKpa < 0 ? 0.0 : pressureKpa;
    if (unit == MeasurementUnit.imperial) {
      return DecodeResult(
        measurementResult: MeasurementResult(clamped * 0.145038, Unit.poundsForcePerSquareInch),
      );
    }
    return DecodeResult(measurementResult: MeasurementResult(clamped, Unit.kilopascals));
  }
}

class FuelTypeDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.isEmpty) {
      throw Exception("Invalid data for FuelTypeDecoder");
    }
    final index = data[0];
    if (index >= fuelTypes.length) {
      throw Exception("Unknown fuel type");
    }
    return DecodeResult(stringResult: fuelTypes[index]);
  }
}

class MaxMafDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.isEmpty) {
      throw Exception("Invalid data for MaxMafDecoder");
    }
    return DecodeResult(
      measurementResult: MeasurementResult(data[0] * 10.0, Unit.gramsPerSecond),
    );
  }
}

class AbsoluteLoadDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final value = ((bytesToInt(data) * 100) / 255.0);
    return DecodeResult(measurementResult: MeasurementResult(value, Unit.percent));
  }
}

class O2SensorsDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final bits = _toBitArray(data);
    if (bits.length < 8) {
      throw Exception("Invalid data for O2SensorsDecoder");
    }
    return DecodeResult(
      stringResult: "${bits.sublist(0, 4)}, ${bits.sublist(4, 8)}",
    );
  }
}

class O2SensorsAltDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final bits = _toBitArray(data);
    if (bits.length < 8) {
      throw Exception("Invalid data for O2SensorsAltDecoder");
    }
    return DecodeResult(
      stringResult: "${bits.sublist(0, 2)}, ${bits.sublist(2, 4)}, ${bits.sublist(4, 6)}, ${bits.sublist(6, 8)}",
    );
  }
}

class OBDComplianceDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    if (data.length < 2) {
      throw Exception("Invalid data for OBDComplianceDecoder");
    }
    final index = data[1];
    if (index >= obdCompliance.length) {
      throw Exception("Unknown OBD compliance");
    }
    return DecodeResult(stringResult: obdCompliance[index]);
  }
}

class FuelStatusDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final bits = _toBitArray(data);
    if (bits.length < 16) {
      throw Exception("Invalid data for FuelStatusDecoder");
    }

    final status1 = _decodeFuelStatus(bits.sublist(0, 8));
    final status2 = _decodeFuelStatus(bits.sublist(8, 16));
    return DecodeResult(codeResult: [status1, status2]);
  }

  StatusCodeMetadata? _decodeFuelStatus(List<int> bits) {
    final setIndices = <int>[];
    for (var i = 0; i < bits.length; i++) {
      if (bits[i] == 1) {
        setIndices.add(i);
      }
    }

    if (setIndices.isEmpty) {
      return StatusCodeMetadata(code: "0", description: fuelStatus["0"]!);
    }
    if (setIndices.length != 1) {
      return null;
    }

    final code = (8 - setIndices.first).toString();
    final description = fuelStatus[code];
    if (description == null) {
      return null;
    }
    return StatusCodeMetadata(code: code, description: description);
  }
}

class AirStatusDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    final bits = _toBitArray(data);
    final setBits = bits.where((b) => b == 1).length;
    if (setBits != 1) {
      throw Exception("Invalid air status response");
    }
    final index = bits.indexOf(1);
    final value = 7 - index;
    return DecodeResult(measurementResult: MeasurementResult(value.toDouble(), Unit.amperes));
  }
}

class MonitorDecoder implements Decoder {
  @override
  DecodeResult decode(Uint8List data, MeasurementUnit unit) {
    var bytes = Uint8List.fromList(data);
    final mon = Monitor();

    final extraBytes = bytes.length % 9;
    if (extraBytes != 0) {
      bytes = Uint8List.fromList(bytes.sublist(0, bytes.length - extraBytes));
    }

    for (int i = 0; i < bytes.length; i += 9) {
      final chunk = Uint8List.fromList(bytes.sublist(i, i + 9));
      final test = _parseMonitorTest(chunk);
      if (test != null && test.tid != null) {
        mon.tests[test.tid!] = test;
      }
    }

    return DecodeResult(measurementMonitor: mon);
  }

  MonitorTest? _parseMonitorTest(Uint8List data) {
    if (data.length < 9) {
      return null;
    }

    final test = MonitorTest();
    final tid = data[1];
    final cid = data[2];

    final testInfo = testIds[tid];
    if (testInfo != null) {
      test.name = testInfo[0];
      test.desc = testInfo[1];
    } else {
      test.name = "TID: \$${tid.toRadixString(16).padLeft(2, '0')} CID: \$${cid.toRadixString(16).padLeft(2, '0')}";
      test.desc = "Unknown";
    }

    final uas = uasIDS[cid];
    if (uas == null) {
      return null;
    }

    final valueRange = Uint8List.fromList(data.sublist(3, 5));
    final minRange = Uint8List.fromList(data.sublist(5, 7));
    final maxRange = Uint8List.fromList(data.sublist(7, 9));

    test.tid = tid;
    test.value = uas.decode(valueRange, MeasurementUnit.metric);
    test.min = uas.decode(minRange, MeasurementUnit.metric).value;
    test.max = uas.decode(maxRange, MeasurementUnit.metric).value;
    return test;
  }
}

List<int> _toBitArray(List<int> data) {
  final bits = <int>[];
  for (final byte in data) {
    for (var i = 0; i < 8; i++) {
      bits.add((byte >> (7 - i)) & 1);
    }
  }
  return bits;
}
