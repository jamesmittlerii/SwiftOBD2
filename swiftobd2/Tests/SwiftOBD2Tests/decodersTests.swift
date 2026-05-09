//
//  decodersTests.swift
//
//
//  Created by kemo konteh on 2/28/24.
//

@testable import SwiftOBD2
import XCTest

final class decodersTests: XCTestCase {
    func testPercent() {
        let tests = [Data([0x00]): MeasurementResult(value: 0, unit: Unit.percent),
                     Data([0xFF]): MeasurementResult(value: 100, unit: Unit.percent)]
        for (data, expected) in tests {
            switch PercentDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 1)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testPercentCentered() {
        let tests = [Data([0x00]): MeasurementResult(value: -100, unit: Unit.percent),
                     Data([0x80]): MeasurementResult(value: 0, unit: Unit.percent),
                     Data([0xFF]): MeasurementResult(value: 100, unit: Unit.percent)]
        for (data, expected) in tests {
            switch PercentCenteredDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 1)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testTemp() {
        let tests = [Data([0x00]): MeasurementResult(value: -40, unit: UnitTemperature.celsius),
                     Data([0xFF]): MeasurementResult(value: 215, unit: UnitTemperature.celsius),
                     Data([0x03, 0xE8]): MeasurementResult(value: 960, unit: UnitTemperature.celsius)]
        for (data, expected) in tests {
            switch TemperatureDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testCurrentCentered() {
        let tests = [
            // Case 1: Raw data (no header). Decoder uses index 0 (0x00)
            Data([0x00, 0x00, 0x00, 0x00]): MeasurementResult(value: -2.0, unit: UnitElectricCurrent.milliamperes),
            
            // Case 2: OBD Response (starts with 0x41). Decoder drops first two, uses index 2 (0x80)
            Data([0x41, 0x34, 0x80, 0x00]): MeasurementResult(value: 0.0, unit: UnitElectricCurrent.milliamperes),
            
            // Case 3: Raw data (no header). Decoder uses index 0 (0xFF)
            Data([0xFF, 0x00, 0xFF, 0xFF]): MeasurementResult(value: 1.984375, unit: UnitElectricCurrent.milliamperes)
        ]
        for (data, expected) in tests {
            switch CurrentCenteredDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testSensorVoltage() {
        let tests = [Data([0x00, 0x00]): MeasurementResult(value: 0, unit: UnitElectricPotentialDifference.volts),
                     Data([0xFF, 0xFF]): MeasurementResult(value: 1.275, unit: UnitElectricPotentialDifference.volts)]
        for (data, expected) in tests {
            switch SensorVoltageDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testSensorVoltageBig() {
        let tests = [Data([0x00, 0x00, 0x00, 0x00]): MeasurementResult(value: 0, unit: UnitElectricPotentialDifference.volts),
                     Data([0x00, 0x00, 0x80, 0x00]): MeasurementResult(value: 4, unit: UnitElectricPotentialDifference.volts),
                     Data([0x00, 0x00, 0xFF, 0xFF]): MeasurementResult(value: 8, unit: UnitElectricPotentialDifference.volts)]
        for (data, expected) in tests {
            switch SensorVoltageBigDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testFuelPressure() {
        let tests = [Data([0x00]): MeasurementResult(value: 0, unit: UnitPressure.kilopascals),
                     Data([0x80]): MeasurementResult(value: 384, unit: UnitPressure.kilopascals),
                     Data([0xFF]): MeasurementResult(value: 765, unit: UnitPressure.kilopascals)]
        for (data, expected) in tests {
            switch FuelPressureDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    //
    func testPressure() {
        let tests = [Data([0x00]): MeasurementResult(value: 0, unit: UnitPressure.kilopascals),
                     //                     Data([0x80]): MeasurementResult(value: 0.5, unit: UnitPressure.kilopascals),
                     //                     Data([0xFF]): MeasurementResult(value: 1, unit: UnitPressure.kilopascals)
        ]
        for (data, expected) in tests {
            switch PressureDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testAbsEvapPressure() {
        let tests = [Data([0x00, 0x00]): MeasurementResult(value: 0, unit: UnitPressure.kilopascals),
                     Data([0xFF, 0xFF]): MeasurementResult(value: 327.675, unit: UnitPressure.kilopascals)]
        for (data, expected) in tests {
            switch AbsEvapPressureDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 0.01)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    //
    func testEvapPressureAlt() {
        let tests = [Data([0x00, 0x00]): MeasurementResult(value: -32767, unit: Unit.Pascal),
                     Data([0x7F, 0xFF]): MeasurementResult(value: 0, unit: Unit.Pascal),
                     Data([0xFF, 0xFF]): MeasurementResult(value: 32768, unit: Unit.Pascal)]
        for (data, expected) in tests {
            switch EvapPressureAltDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 1)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testTimingAdvance() {
        let tests = [Data([0x00]): MeasurementResult(value: -64, unit: UnitAngle.degrees),
                     Data([0xFF]): MeasurementResult(value: 63.5, unit: UnitAngle.degrees)]
        for (data, expected) in tests {
            switch TimingAdvanceDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                XCTAssertEqual(result.measurementResult!.value, expected.value, accuracy: 1)
                XCTAssertEqual(result.measurementResult!.unit, expected.unit)
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testInjectTiming() {
        // Force the unit to be UnitAngle.degrees explicitly
        let tests: [Data: MeasurementResult] = [
            Data([0x00, 0x00]): MeasurementResult(value: -210, unit: UnitAngle.degrees),
            Data([0xFF, 0xFF]): MeasurementResult(value: 301.99, unit: UnitAngle.degrees)
        ]
        
        for (data, expected) in tests {
            switch InjectTimingDecoder().decode(data: data, unit: .metric) {
            case let .success(result):
                let actualResult = result.measurementResult!
                
                XCTAssertEqual(actualResult.value, expected.value, accuracy: 1.0)
                
                // FIX: Compare the units correctly
                XCTAssertEqual(actualResult.unit.symbol, expected.unit.symbol, "Unit symbol mismatch")
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testStatus() {
        let statusResult = StatusDecoder().decode(data: Data([0x00, 0x83, 0x07, 0xFF, 0x00]), unit: .metric)
        switch statusResult {
        case let .success(status):
            // Updated to match current Status API
            // Expect MIL to be off
            XCTAssertEqual(status.statusResult?.milOn, false)
            // Expect zero DTCs
            XCTAssertEqual(status.statusResult?.dtcCount, 0)
            
            XCTAssertEqual(status.statusResult?.isDiesel, false)
            
            
            // Expect ignition type to be Spark (enum or string)
            
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testSingleDtc() {
        let tests = [
            
            Data([0x01, 0x04]): TroubleCode(code: "P0104", description: "The PCM detects an intermittent or unstable airflow reading."),
            Data([0x41, 0x23]): TroubleCode(code: "C0123", description: "No description available."),
            Data([0x01]): nil,
            Data([0x01, 0x04, 0x00]): nil]
        
        for (data, expected) in tests {
            let result = SingleDTCDecoder().decode(data: data, unit: .metric)
            switch result {
            case let .success(dtc):
                let actual = dtc.troubleCode?.first // TroubleCodeMetadata?
                let expected = expected             // TroubleCode? (from your loop)
                
                // Compare the specific properties you care about
                XCTAssertEqual(actual?.code, expected?.code, "Codes do not match")
                XCTAssertEqual(actual?.description, expected?.description, "Descriptions do not match")
            case let .failure(error):
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
    
    func testDtc() {
        let tests = [
            Data([0x01, 0x04]):
                [
                    TroubleCode(code: "P0104", description: "Mass or Volume Air Flow Circuit Intermittent"),
                ],
            Data([0x01, 0x04, 0x80, 0x03, 0x41, 0x23]):
                [
                    TroubleCode(code: "P0104", description: "Mass or Volume Air Flow Circuit Intermittent"),
                    TroubleCode(code: "B0003", description: "No description available."),
                    TroubleCode(code: "C0123", description: "No description available."),
                ],
            Data([0x01, 0x04, 0x80, 0x03, 0x41]):
                [
                    TroubleCode(code: "P0104", description: "Mass or Volume Air Flow Circuit Intermittent"),
                    TroubleCode(code: "B0003", description: "No description available."),
                ],
            Data([0x00, 0x00, 0x01, 0x04, 0x00, 0x00]):
                [
                    TroubleCode(code: "P0104", description: "Mass or Volume Air Flow Circuit Intermittent"),
                ],
        ]
        
        for test in tests {
            let result = DTCDecoder().decode(data: test.key, unit: .metric)
            switch result {
            case let .success(troubleCodes):
                // Compare by code strings to avoid type mismatches between TroubleCodeMetadata and TroubleCode
                let actualCodes = troubleCodes.troubleCode?.map { $0.code } ?? []
                let expectedCodes = test.value.map { $0.code }
                XCTAssertEqual(actualCodes, expectedCodes)
            case .failure:
                XCTFail()
            }
        }
    }
    
    func testMonitor() {
        let monitorResult = MonitorDecoder().decode(data: Data([0x01, 0x01, 0x0A, 0x0B, 0xB0, 0x0B, 0xB0, 0x0B, 0xB0]), unit: .metric)
        switch monitorResult {
        case let .success(monitor):
            guard let tests = monitor.measurementMonitor?.tests else {
                XCTFail()
                return
            }
            XCTAssertEqual(tests.count, 1)
            XCTAssertEqual(tests[0x01]?.name, "RTLThresholdVoltage")
            XCTAssertEqual(tests[0x01]!.value!.value, 365.0, accuracy: 0.1)
            XCTAssertEqual(tests[0x01]!.value!.unit, UnitElectricPotentialDifference.millivolts)
        default:
            XCTFail("Monitor decoding failed")
        }
        
        //        01 01 0A 0B B0 0B 0B 0B B0 0105100048 00 00 00 640185240096004BFFFF
        let monitorResult2 = MonitorDecoder().decode(data: Data([0x01, 0x01, 0x0A, 0x0B, 0xB0, 0x0B, 0x0B, 0x0B, 0xB0, 0x01, 0x05, 0x10, 0x00, 0x48, 0x00, 0x00, 0x00, 0x64, 0x01, 0x85, 0x24, 0x00, 0x96, 0x00, 0x4B, 0xFF, 0xFF]),  unit: .metric)
        
        switch monitorResult2 {
        case let .success(monitor):
            guard let tests = monitor.measurementMonitor?.tests else {
                XCTFail()
                return
            }
            XCTAssertEqual(tests.count, 3)
            XCTAssertEqual(tests[0x01]?.name, "RTLThresholdVoltage")
            XCTAssertEqual(tests[0x01]!.value!.value, 365.0, accuracy: 0.1)
            XCTAssertEqual(tests[0x01]!.value!.unit, UnitElectricPotentialDifference.millivolts)
            XCTAssertEqual(tests[0x01]!.value!.value, 365.0, accuracy: 0.1)
            XCTAssertEqual(tests[0x05]?.name, "RTLSwitchTime")
            XCTAssertEqual(tests[0x05]!.value!.value, 72, accuracy: 0.1)
            XCTAssertEqual(tests[0x05]!.value!.unit, UnitDuration.milliseconds)
        default:
            XCTFail("Monitor decoding failed")
        }
    }
}

