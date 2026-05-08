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

    test('StringDecoder', () {
      final data = Uint8List.fromList([0x41, 0x42, 0x43, 0x2D, 0x31]); // 'ABC-1'
      final result = StringDecoder().decode(data, MeasurementUnit.metric);
      expect(result.stringResult, "ABC1");
    });

    test('UasDecoder', () {
      final data = Uint8List.fromList([0x00, 0x05]); // 5
      final result = UasDecoder(0x01).decode(data, MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(5, 0.01));
      expect(result.measurementResult!.unit.symbol, Unit.count.symbol);
      
      expect(() => UasDecoder(0xFF).decode(data, MeasurementUnit.metric), throwsException);
    });

    test('Uas convertToImperial', () {
      final uasTemp = uasIDS[0x16]!; // Celsius
      final dataTemp = Uint8List.fromList([0x00, 0x80]); // 128 * 0.1 - 40 = -27.2 C
      final resF = uasTemp.decode(dataTemp, MeasurementUnit.imperial);
      expect(resF.value, closeTo(-16.96, 0.1));

      final uasKm = uasIDS[0x25]!; // Kilometers
      final dataKm = Uint8List.fromList([0x00, 0x64]); // 100
      final resMi = uasKm.decode(dataKm, MeasurementUnit.imperial);
      expect(resMi.value, closeTo(62.1371, 0.1));

      final uasKmh = uasIDS[0x09]!; // km/h
      final resMph = uasKmh.decode(dataKm, MeasurementUnit.imperial);
      expect(resMph.value, closeTo(62.1371, 0.1));

      final uasKpa = uasIDS[0x1A]!; // kPa
      final dataKpa = Uint8List.fromList([0x00, 0x64]); // 100
      final resPsi = uasKpa.decode(dataKpa, MeasurementUnit.imperial);
      expect(resPsi.value, closeTo(14.5038, 0.1));
      
      final uasGps = uasIDS[0x27]!; // g/s
      final dataGps = Uint8List.fromList([0x27, 0x10]); // 10000 * 0.01 = 100
      final resLbm = uasGps.decode(dataGps, MeasurementUnit.imperial);
      expect(resLbm.value, closeTo(13.2277, 0.1));
      
      final uasBar = Uas(signed: false, scale: 1.0, unit: Unit.bar);
      final resBar = uasBar.decode(Uint8List.fromList([0x01]), MeasurementUnit.imperial);
      expect(resBar.value, closeTo(14.5038, 0.1));
      
      final uasLiters = Uas(signed: false, scale: 1.0, unit: Unit.litersPerHour);
      final resGal = uasLiters.decode(Uint8List.fromList([0x01]), MeasurementUnit.imperial);
      expect(resGal.value, closeTo(0.264172, 0.1));
    });

    test('Uas Signed negative decode', () {
      final uas = uasIDS[0x81]!; // Signed count
      final data = Uint8List.fromList([0xFF]); // -1
      final res = uas.decode(data, MeasurementUnit.metric);
      expect(res.value, closeTo(-1, 0.1));
    });

    test('EvapPressureDecoder', () {
      var result = EvapPressureDecoder().decode(Uint8List.fromList([0x00, 0x00]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(0, 0.01));

      result = EvapPressureDecoder().decode(Uint8List.fromList([0x80, 0x00]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(-8192, 0.01));
      
      result = EvapPressureDecoder().decode(Uint8List.fromList([0x01, 0x00]), MeasurementUnit.imperial);
      expect(result.measurementResult!.value, closeTo(64 * 0.145038, 0.01));

      expect(() => EvapPressureDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric), throwsException);
    });

    test('FuelRateDecoder', () {
      final result = FuelRateDecoder().decode(Uint8List.fromList([0x01, 0x00]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(12.8, 0.01));
      
      final resultImp = FuelRateDecoder().decode(Uint8List.fromList([0x01, 0x00]), MeasurementUnit.imperial);
      expect(resultImp.measurementResult!.value, closeTo(12.8 * 0.264172, 0.01));

      expect(() => FuelRateDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric), throwsException);
    });

    test('GMEngineOilPressureDecoder', () {
      final result = GMEngineOilPressureDecoder().decode(Uint8List.fromList([0x10]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(63.76, 0.1));

      final resultImp = GMEngineOilPressureDecoder().decode(Uint8List.fromList([0x10]), MeasurementUnit.imperial);
      expect(resultImp.measurementResult!.value, closeTo(63.76 * 0.145038, 0.1));

      expect(() => GMEngineOilPressureDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('GMACPressureDecoder', () {
      final result = GMACPressureDecoder().decode(Uint8List.fromList([0x10]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(100.5, 0.1));

      final resultImp = GMACPressureDecoder().decode(Uint8List.fromList([0x10]), MeasurementUnit.imperial);
      expect(resultImp.measurementResult!.value, closeTo(100.5 * 0.145038, 0.1));

      expect(() => GMACPressureDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('FuelTypeDecoder', () {
      final result = FuelTypeDecoder().decode(Uint8List.fromList([0x01]), MeasurementUnit.metric);
      expect(result.stringResult, "Gasoline");

      expect(() => FuelTypeDecoder().decode(Uint8List.fromList([0xFF]), MeasurementUnit.metric), throwsException);
      expect(() => FuelTypeDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('MaxMafDecoder', () {
      final result = MaxMafDecoder().decode(Uint8List.fromList([0x10]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(160, 0.1));

      expect(() => MaxMafDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('AbsoluteLoadDecoder', () {
      final result = AbsoluteLoadDecoder().decode(Uint8List.fromList([0x01, 0x00]), MeasurementUnit.metric);
      expect(result.measurementResult!.value, closeTo(100.39, 0.01));
    });

    test('O2SensorsDecoder', () {
      final result = O2SensorsDecoder().decode(Uint8List.fromList([0x81]), MeasurementUnit.metric);
      expect(result.stringResult, "[1, 0, 0, 0], [0, 0, 0, 1]");

      expect(() => O2SensorsDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('O2SensorsAltDecoder', () {
      final result = O2SensorsAltDecoder().decode(Uint8List.fromList([0x81]), MeasurementUnit.metric);
      expect(result.stringResult, "[1, 0], [0, 0], [0, 0], [0, 1]");

      expect(() => O2SensorsAltDecoder().decode(Uint8List.fromList([]), MeasurementUnit.metric), throwsException);
    });

    test('OBDComplianceDecoder', () {
      final result = OBDComplianceDecoder().decode(Uint8List.fromList([0x00, 0x01]), MeasurementUnit.metric);
      expect(result.stringResult, "OBD-II as defined by the CARB");

      expect(() => OBDComplianceDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric), throwsException);
      expect(() => OBDComplianceDecoder().decode(Uint8List.fromList([0x00, 0xFF]), MeasurementUnit.metric), throwsException);
    });

    test('FuelStatusDecoder', () {
      final result = FuelStatusDecoder().decode(Uint8List.fromList([0x01, 0x02]), MeasurementUnit.metric); 
      expect(result.codeResult![0]!.code, "1");
      expect(result.codeResult![1]!.code, "2");

      final empty = FuelStatusDecoder().decode(Uint8List.fromList([0x00, 0x00]), MeasurementUnit.metric);
      expect(empty.codeResult![0]!.code, "0");
      expect(empty.codeResult![1]!.code, "0");

      final multi = FuelStatusDecoder().decode(Uint8List.fromList([0x03, 0x00]), MeasurementUnit.metric);
      expect(multi.codeResult![0], isNull);

      expect(() => FuelStatusDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric), throwsException);
    });

    test('AirStatusDecoder', () {
      final result = AirStatusDecoder().decode(Uint8List.fromList([0x01]), MeasurementUnit.metric); 
      expect(result.measurementResult!.value, 0);

      expect(() => AirStatusDecoder().decode(Uint8List.fromList([0x03]), MeasurementUnit.metric), throwsException);
    });

    test('TemperatureDecoder Imperial', () {
      final data = Uint8List.fromList([0xFF]);
      final result = TemperatureDecoder().decode(data, MeasurementUnit.imperial);
      expect(result.measurementResult!.value, closeTo(419.0, 0.1));
    });

    test('FuelPressureDecoder Imperial', () {
      final data = Uint8List.fromList([0xFF]);
      final result = FuelPressureDecoder().decode(data, MeasurementUnit.imperial);
      expect(result.measurementResult!.value, closeTo(110.95, 0.1));
    });

    test('PressureDecoder Imperial', () {
      final data = Uint8List.fromList([0xFF]);
      final result = PressureDecoder().decode(data, MeasurementUnit.imperial);
      expect(result.measurementResult!.value, closeTo(36.98, 0.1));
    });

    test('AbsEvapPressureDecoder Imperial', () {
      final data = Uint8List.fromList([0xFF, 0xFF]);
      final result = AbsEvapPressureDecoder().decode(data, MeasurementUnit.imperial);
      expect(result.measurementResult!.value, closeTo(47.52, 0.1));
    });

    test('StatusDecoder Diesel', () {
      final data = Uint8List.fromList([0x00, 0x08, 0x00, 0x00, 0x00]);
      final result = StatusDecoder().decode(data, MeasurementUnit.metric);
      expect(result.statusResult!.ignitionType, "Compression");
      expect(result.statusResult!.monitors.length, 9);
      
      expect(() => StatusDecoder().decode(Uint8List.fromList([0x00]), MeasurementUnit.metric), throwsException);
    });

    test('DtcDecoder severity fallbacks', () {
      final data = Uint8List.fromList([0x00, 0x87]); // P0087
      final result = SingleDtcDecoder().decode(data, MeasurementUnit.metric);
      expect(result.troubleCodes!.first.severity, "Critical");

      final data2 = Uint8List.fromList([0x01, 0x71]); // P0171
      final result2 = SingleDtcDecoder().decode(data2, MeasurementUnit.metric);
      expect(result2.troubleCodes!.first.severity, "High");

      final data3 = Uint8List.fromList([0x04, 0x11]); // P0411
      final result3 = SingleDtcDecoder().decode(data3, MeasurementUnit.metric);
      expect(result3.troubleCodes!.first.severity, "Low");
      
      final data4 = Uint8List.fromList([0x02, 0x00]); // P0200
      final result4 = SingleDtcDecoder().decode(data4, MeasurementUnit.metric);
      expect(result4.troubleCodes!.first.severity, "Moderate");
    });

    test('MonitorDecoder unknown TID and CID', () {
      final result = MonitorDecoder().decode(
        Uint8List.fromList([0x01, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        MeasurementUnit.metric,
      );
      expect(result.measurementMonitor!.tests.length, 0);
    });

    test('MeasurementUnit next', () {
      expect(MeasurementUnit.metric.next, MeasurementUnit.imperial);
      expect(MeasurementUnit.imperial.next, MeasurementUnit.metric);
    });

    test('MonitorTest passed', () {
      final t = MonitorTest();
      expect(t.passed, false);
      expect(t.isNull, true);
      
      t.tid = 1;
      t.value = MeasurementResult(10, Unit.count);
      t.min = 5;
      t.max = 15;
      expect(t.passed, true);
      expect(t.isNull, false);
      expect(t.toString().contains("PASSED"), true);

      t.value = MeasurementResult(20, Unit.count);
      expect(t.passed, false);
      expect(t.toString().contains("FAILED"), true);
    });
  });
}

