import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

void main() {
  group('Decoder Tests', () {
    test('PercentDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(0, Unit.percent),
        [0xFF]: MeasurementResult(100, Unit.percent),
      };

      tests.forEach((data, expected) {
        final result = PercentDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 1));
      });
    });

    test('PercentCenteredDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(-100, Unit.percent),
        [0x80]: MeasurementResult(0, Unit.percent),
        [0xFF]: MeasurementResult(100, Unit.percent),
      };

      tests.forEach((data, expected) {
        final result = PercentCenteredDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 1));
      });
    });

    test('TemperatureDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(-40, Unit.celsius), // Assuming celsius output
        [0xFF]: MeasurementResult(215, Unit.celsius),
        [0x03, 0xE8]: MeasurementResult(960, Unit.celsius), // For 2 bytes temp
      };

      tests.forEach((data, expected) {
        final result = TemperatureDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.01));
      });
    });

    test('CurrentCenteredDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(-2, Unit.milliamperes),
        [0x80]: MeasurementResult(0, Unit.milliamperes),
        [0xFF]: MeasurementResult(2, Unit.milliamperes),
      };

      tests.forEach((data, expected) {
        final result = CurrentCenteredDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.05));
      });
    });

    test('SensorVoltageDecoder', () {
      final tests = {
        [0x00, 0x00]: MeasurementResult(0, Unit.volts),
        [0xFF, 0xFF]: MeasurementResult(1.275, Unit.volts),
      };

      tests.forEach((data, expected) {
        final result = SensorVoltageDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.01));
      });
    });

    test('FuelPressureDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(0, Unit.kilopascals),
        [0x80]: MeasurementResult(384, Unit.kilopascals),
        [0xFF]: MeasurementResult(765, Unit.kilopascals),
      };

      tests.forEach((data, expected) {
        final result = FuelPressureDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.01));
      });
    });

    test('SensorVoltageBigDecoder', () {
      final tests = {
        [0x00, 0x00, 0x00, 0x00]: MeasurementResult(0, Unit.volts),
        [0x00, 0x00, 0x80, 0x00]: MeasurementResult(4, Unit.volts),
        [0x00, 0x00, 0xFF, 0xFF]: MeasurementResult(8, Unit.volts),
      };

      tests.forEach((data, expected) {
        final result = SensorVoltageBigDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.01));
      });
    });

    test('PressureDecoder', () {
      final result = PressureDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(0, 0.01));
      expect(result.measurementResult!.unit.symbol, Unit.kilopascals.symbol);
    });

    test('AbsEvapPressureDecoder', () {
      final tests = {
        [0x00, 0x00]: MeasurementResult(0, Unit.kilopascals),
        [0xFF, 0xFF]: MeasurementResult(327.675, Unit.kilopascals),
      };

      tests.forEach((data, expected) {
        final result = AbsEvapPressureDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 0.01));
      });
    });

    test('EvapPressureAltDecoder', () {
      final tests = {
        [0x00, 0x00]: MeasurementResult(-32767, Unit.pascal),
        [0x7F, 0xFF]: MeasurementResult(0, Unit.pascal),
        [0xFF, 0xFF]: MeasurementResult(32768, Unit.pascal),
      };

      tests.forEach((data, expected) {
        final result = EvapPressureAltDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 1));
      });
    });

    test('TimingAdvanceDecoder', () {
      final tests = {
        [0x00]: MeasurementResult(-64, Unit.degrees),
        [0xFF]: MeasurementResult(63.5, Unit.degrees),
      };

      tests.forEach((data, expected) {
        final result = TimingAdvanceDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 1));
      });
    });

    test('InjectTimingDecoder', () {
      final tests = {
        [0x00, 0x00]: MeasurementResult(-2100, Unit.degrees),
        [0xFF, 0xFF]: MeasurementResult(4453.5, Unit.degrees),
      };

      tests.forEach((data, expected) {
        final result = InjectTimingDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.measurementResult!.value, closeTo(expected.value, 1));
      });
    });

    test('StatusDecoder', () {
      final data = Uint8List.fromList([0x00, 0x83, 0x07, 0xFF, 0x00]);
      final result = StatusDecoder().decode(data, MeasurementUnit.metric);
      
      expect(result.statusResult!.milOn, false);
      expect(result.statusResult!.dtcCount, 0);
      expect(result.statusResult!.ignitionType, "Spark");
    });

    test('DtcDecoder', () {
      final data = Uint8List.fromList([0x01, 0x04, 0x80, 0x03, 0x41, 0x23]);
      final result = DtcDecoder().decode(data, MeasurementUnit.metric);
      
      final codes = result.troubleCodes!.map((t) => t.code).toList();
      expect(codes, containsAll(["P0104", "B0003", "C0123"]));
    });

    test('SingleDtcDecoder', () {
      final tests = {
        [0x01, 0x04]: "P0104",
        [0x41, 0x23]: "C0123",
      };

      tests.forEach((data, expectedCode) {
        final result = SingleDtcDecoder().decode(Uint8List.fromList(data), MeasurementUnit.metric);
        expect(result.troubleCodes, isNotNull);
        expect(result.troubleCodes!.first.code, expectedCode);
      });
    });

    test('MonitorDecoder', () {
      final result = MonitorDecoder().decode(
        Uint8List.fromList([0x01, 0x01, 0x0A, 0x0B, 0xB0, 0x0B, 0xB0, 0x0B, 0xB0]),
        MeasurementUnit.metric,
      );
      expect(result.measurementMonitor, isNotNull);
      expect(result.measurementMonitor!.tests.length, 1);
      expect(result.measurementMonitor!.tests[0x01]?.name, "RTLThresholdVoltage");
      expect(result.measurementMonitor!.tests[0x01]?.value?.value, closeTo(365.0, 0.1));
    });
  });
}
