//
//  File.swift
//
//
//  Created by kemo konteh on 3/16/24.
//

import Foundation
import OSLog
import CoreBluetooth

enum CommandAction {
    case setHeaderOn
    case setHeaderOff
    case echoOn
    case echoOff
}

struct MockECUSettings {
    var headerOn = true
    var echo = false
    var vinNumber = ""
}

// Per-mock-session evolving state
private struct MockSessionState {
    var testStart: Date?
    // Evolving accumulators for realism
    var accumulatedSeconds: Double = 0
    var accumulatedMeters: Double = 0
    var lastTick: Date?
}

class MOCKComm: CommProtocol {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app", category: "MOCKComm")

    @Published var connectionState: ConnectionState = .disconnected
    var connectionStatePublisher: Published<ConnectionState>.Publisher { $connectionState }
    var obdDelegate: OBDServiceDelegate?

    var ecuSettings: MockECUSettings = .init()
    private var sessionState = MockSessionState()

    func sendCommand(_ command: String, retries _: Int = 3) async throws -> [String] {
        //obdInfo("Sending command: \(command)")
        var header = ""

        let prefix = String(command.prefix(2))
        if prefix == "01" || prefix == "06" || prefix == "09" || prefix == "22"{
            var response: String = ""
            if ecuSettings.headerOn {
                header = "7E8"
            }
            
            if prefix == "22" {
                guard let value = makeMockResponse(for: command) else {
                    return ["No Data"]
                    
                }
                response.append(value + " ")
                
            }
            else {
                for i in stride(from: 2, to: command.count, by: 2) {
                    let index = command.index(command.startIndex, offsetBy: i)
                    let nextIndex = command.index(command.startIndex, offsetBy: i + 2)
                    let subCommand = prefix + String(command[index..<nextIndex])
                    guard let value = makeMockResponse(for: subCommand) else {
                        return ["No Data"]
                        
                    }
                    response.append(value + " ")
                }
            }
            guard var mode = Int(command.prefix(2)) else {
                return [""]
            }
            mode = mode + 40

            if response.count > 18 {
                let chunks = response.chunked(by: 15)

                var ff = chunks[0]

                var totalLength = 0

                let ffLength = ff.replacingOccurrences(of: " ", with: "").count / 2

                totalLength += ffLength

                var cf = Array(chunks.dropFirst())
                totalLength += cf.joined().replacingOccurrences(of: " ", with: "").count

                var lengthHex = String(format: "%02X", totalLength - 1)

                if lengthHex.count % 2 != 0 {
                    lengthHex = "0" + lengthHex
                }

                lengthHex = "10 " + lengthHex
                ff = lengthHex + " " + String(mode) + " " + ff

                var assembledFrame: [String] = [ff]
                var cfCount = 33
                for i in 0..<cf.count {
                    let length = String(format: "%02X", cfCount)
                    cfCount += 1
                    cf[i] = length + " " + cf[i]
                    assembledFrame.append(cf[i])
                }

                for i in 0..<assembledFrame.count {
                    assembledFrame[i] = header + " " + assembledFrame[i]
                    while assembledFrame[i].count < 28 {
                        assembledFrame[i].append("00 ")
                    }
                }

                if ecuSettings.echo {
                    assembledFrame.insert(" \(command)", at: 0)
                }
                return assembledFrame.map { String($0) }
            } else {
                let lengthHex = String(format: "%02X", response.count / 3)
                response = header + " " + lengthHex + " "  + String(mode) + " " + response
                while response.count < 28 {
                    response.append("00 ")
                }
                if ecuSettings.echo {
                    response = " \(command)" + response
                }
                return [response]
            }
        } else  if command.hasPrefix("AT") {
            let action = command.dropFirst(2)
            var response = {
                switch action {

                case " SH 7E0", "D", "L0", "AT1", "SP0", "SP6", "STFF", "S0":
                    return ["OK"]

                case "Z":
                    return ["ELM327 v1.5"]

                case "H1":
                    ecuSettings.headerOn = true
                    return ["OK"]

                case "H0":
                    ecuSettings.headerOn = false
                    return ["OK"]

                case "E1":
                    ecuSettings.echo = true
                    return ["OK"]

                case "E0":
                    ecuSettings.echo = false
                    return ["OK"]

                case "DPN":
                    return ["06"]
                    
                case "AL":
                    return ["OK"]

                case "RV":
                    // Simulate alternator voltage with gentle drift
                    let v = 13.6 + smoothNoise(seed: 1, scale: 0.15)
                    return [String(format: "%.2f", max(12.2, min(14.6, v)))]

                // ✅ Handle ATSTxx (timeout byte)
                default:
                    if action.hasPrefix("ST") {
                        let hexByte = String(action.dropFirst(2))   // get the "xx"
                        if UInt8(hexByte, radix: 16) != nil {
                            //ecuSettings.timeout = hexByte
                            return ["OK"]
                        } else {
                            return ["NO DATA"]  // malformed timeout
                        }
                    }
                    return ["NO DATA"]
                }
            }()
            if ecuSettings.echo {
                response .insert(command, at: 0)
            }
            return response

        } else if command == "03" {
            
            // Mixed-severity sample codes
            let dtcs = [
                
                    "P0300",
                    "P0170",
                    "P0101",
                    "P0104",
                    "P0207",
                    "P0411",
                    "P0420"
                    
        
            ]

            // Encode DTCs to J1979 bytes
            func encodeDTC(_ dtc: String) -> [UInt8] {
                let letters: [Character: UInt8] = [
                    "P": 0x0,
                    "C": 0x1,
                    "B": 0x2,
                    "U": 0x3
                ]

                let systemNibble = letters[dtc.first!] ?? 0
                let digits = dtc.dropFirst()

                let d1 = UInt8(String(digits.prefix(1)), radix: 16)!
                let d2 = UInt8(String(digits.dropFirst().prefix(1)), radix: 16)!
                let d3 = UInt8(String(digits.dropFirst(2)), radix: 16)!

                // Byte A = system + d1 + d2
                let byteA = (systemNibble << 6) | (d1 << 4) | d2
                let byteB = d3
                return [byteA, byteB]
            }

            // Build full data payload
            var payload: [UInt8] = []
            payload.append(0x43)                // Mode 03 response
            payload.append(UInt8(dtcs.count))   // Count

            for dtc in dtcs {
                let codeBytes = encodeDTC(dtc)
                payload.append(contentsOf: codeBytes)
            }

            // Total payload = 14 bytes → must be multi-frame

            // ---- FRAME 1: First Frame ----
            // PCI: 10 LL   (LL = total payload)
            let totalLen = UInt8(payload.count)
            let frame1Bytes = [0x10, totalLen] + Array(payload.prefix(6))
            let frame1 = "7E8 " + frame1Bytes.map { String(format: "%02X", $0) }.joined(separator: " ")

            // ---- FRAME 2: Consecutive Frame #1 ----
            let frame2Bytes = [0x21] + Array(payload.dropFirst(6).prefix(7))
            let frame2 = "7E8 " + frame2Bytes.map { String(format: "%02X", $0) }.joined(separator: " ")

            // ---- FRAME 3: Consecutive Frame #2 ----
            var remaining = Array(payload.dropFirst(6 + 7))
            while remaining.count < 7 { remaining.append(0x00) } // pad to 7
            let frame3Bytes = [0x22] + remaining
            let frame3 = "7E8 " + frame3Bytes.map { String(format: "%02X", $0) }.joined(separator: " ")

            return [frame1, frame2, frame3]
        }else {
            guard var response = makeRawMockResponse(for: command) else {
                return ["No Data"]
            }
            response = command + response  + "\r\n\r\n>"
            var lines = response
                    .components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            lines.removeLast()
            return lines
        }
    }

    func disconnectPeripheral() {
        connectionState = .disconnected
        obdDelegate?.connectionStateChanged(state: .disconnected)
    }

    func connectAsync(timeout _: TimeInterval, peripheral _: CBPeripheral? = nil) async throws {
        connectionState = .connectedToAdapter
        obdDelegate?.connectionStateChanged(state: .connectedToAdapter)
    }

    func scanForPeripherals() async throws {
        // Mock communication exposes no discovery phase; tests connect to the in-memory adapter immediately.
    }
}

// MARK: - Per-session mock generation (moved from OBDCommand extension)

private extension MOCKComm {
    enum OscillationWaveform {
        case sine
        case cosine
    }

    // Session time helpers
    func sessionElapsed(now: Date = Date()) -> Double {
        // Initialize start on first call
        if sessionState.testStart == nil {
            sessionState.testStart = now
            sessionState.lastTick = now
            sessionState.accumulatedSeconds = 0
            sessionState.accumulatedMeters = 0
        }

        // Reset after 2 minutes
        if let start = sessionState.testStart, now.timeIntervalSince(start) >= 120 {
            obdInfo("Mock session exceeded 2 minutes. Resetting session state.", category: .communication)
            sessionState = MockSessionState(testStart: now, accumulatedSeconds: 0, accumulatedMeters: 0, lastTick: now)
        }

        let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)

        // Update accumulators
        let dt: Double
        if let last = sessionState.lastTick {
            dt = now.timeIntervalSince(last)
        } else {
            dt = 0
        }
        sessionState.lastTick = now
        sessionState.accumulatedSeconds += max(0, dt)

        // Integrate distance from speed (km/h → m/s)
        let vKmh = currentMockSpeed(now: now)
        let vMs = vKmh / 3.6
        sessionState.accumulatedMeters += vMs * dt
        return elapsed
    }

    // Smooth pseudo-noise tied to elapsed time
    func smoothNoise(seed: Double, scale: Double) -> Double {
        let t = sessionElapsed()
        // Two sine waves with different frequencies blended
        let n = sin((t + seed) * 0.2) * 0.6 + sin((t * 0.07) + seed * 3.1) * 0.4
        return n * scale
    }

    // Reusable speed generator using the per-session timeline
    func currentMockSpeed(now: Date = Date()) -> Double {
        if sessionState.testStart == nil {
            sessionState.testStart = now
        }
        let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)

        let rampDuration: TimeInterval = 15.0
        let minSpeed = 20.0
        let maxSpeed = 70.0
        let midpoint = (minSpeed + maxSpeed) / 2.0 // 45
        let amplitude = (maxSpeed - minSpeed) / 2.0 // 25

        if elapsed < rampDuration {
            // Linear ramp 0 → 20
            return max(0.0, min(minSpeed, (elapsed / rampDuration) * minSpeed))
        } else {
            // Sine oscillation around midpoint with 30s period
            let oscillationPeriod: TimeInterval = 30.0
            let phase = 2.0 * Double.pi * ((elapsed - rampDuration).truncatingRemainder(dividingBy: oscillationPeriod) / oscillationPeriod)
            return midpoint + amplitude * sin(phase)
        }
    }

    // Reusable RPM generator based on speed and 3-gear model; reaches 8000 at top of each band
    func currentMockRPM(fromSpeed speedValue: Double) -> Double {
        if speedValue <= 0.5 {
            return 800.0 // idle
        } else if speedValue < 20.0 {
            // Gear 1: 0→20 hits 8000
            return 800.0 + 360.0 * speedValue
        } else if speedValue < 50.0 {
            // Gear 2: 20→50 hits 8000 (starting around ~1500 at 20)
            return 1500.0 + (6500.0 / 30.0) * (speedValue - 20.0)
        } else {
            // Gear 3: 50→70 hits 8000 (starting around ~1800 at 50)
            return 1800.0 + 310.0 * (speedValue - 50.0)
        }
    }

    func mockTemperatureRampResponse(pid: String, maxCelsius: Double) -> String {
        let elapsed = min(max(sessionElapsed(), 0.0), 60.0)
        let tempC = (elapsed / 60.0) * maxCelsius
        let raw = UInt8(clamping: Int((tempC + 40.0).rounded()))
        return "\(pid) " + String(format: "%02X", raw)
    }

    func mockFuelTrimResponse(pid: String, waveform: OscillationWaveform, frequency: Double, amplitude: Double) -> String {
        let phase = sessionElapsed() * frequency
        let oscillation: Double
        switch waveform {
        case .sine:
            oscillation = sin(phase)
        case .cosine:
            oscillation = cos(phase)
        }
        let trim = 128 + Int((oscillation * amplitude * 255.0).rounded())
        let trimByte = UInt8(clamping: trim)
        return "\(pid) " + String(format: "%02X", trimByte)
    }

    func mockO2SensorResponse(
        pid: String,
        baseVoltage: Double,
        voltageSeed: Double,
        voltageScale: Double,
        trimSeed: Double,
        trimScale: Double
    ) -> String {
        let voltage = max(0.1, min(0.9, baseVoltage + smoothNoise(seed: voltageSeed, scale: voltageScale)))
        let voltageByte = UInt8(clamping: Int((voltage / 1.275) * 255.0))
        let trimByte = UInt8(clamping: 128 + Int(smoothNoise(seed: trimSeed, scale: trimScale) * 255.0))
        return "\(pid) " + String(format: "%02X %02X", voltageByte, trimByte)
    }

    func mockAccumulatedDistanceResponse(pid: String) -> String {
        _ = sessionElapsed()
        let kilometers = sessionState.accumulatedMeters / 1000.0
        let raw = max(0, min(65535, Int(kilometers.rounded())))
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "\(pid) " + String(format: "%02X %02X", highByte, lowByte)
    }

    func mockSignedPressureResponse(pid: String, baseline: Double, seed: Double, scale: Double) -> String {
        let pressure = Int(baseline + smoothNoise(seed: seed, scale: scale) * 100.0)
        let raw = UInt16(bitPattern: Int16(clamping: pressure))
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = Int(raw & 0xFF)
        return "\(pid) " + String(format: "%02X %02X", highByte, lowByte)
    }

    func mockCenteredTrimResponse(pid: String, seed: Double, scale: Double) -> String {
        let trimByte = UInt8(clamping: 128 + Int(smoothNoise(seed: seed, scale: scale) * 255.0))
        return "\(pid) " + String(format: "%02X 00", trimByte)
    }

    // MARK: - Mock Response Helpers by Command Type

    func makeMockResponse(for command: String) -> String? {
        guard let obd2Command = OBDCommand.from(command: command) else {
            obdWarning("Invalid mock command: \(command)", category: .communication)
            return nil // Return nil for invalid commands
        }

        switch obd2Command {
        case .GMmode22(let gmCommand):
            return handleGMMode22MockResponse(for: gmCommand)
        case .mode1(let mode1Command):
            return handleMode1MockResponse(for: mode1Command)
        case .mode6(let mode6Command):
            return handleMode6MockResponse(for: mode6Command)
        case .mode9(let mode9Command):
            return handleMode9MockResponse(for: mode9Command)
        default:
            obdDebug("No specific mock response handler for command: \(command)", category: .communication)
            return nil
        }
    }

    private func handleGMMode22MockResponse(for command: OBDCommand.GMMode22) -> String? {
        switch command {
        case .ACHighPressure:
            return "11 44 32 00"
        case .engineOilPressure:
            return "14 70 31 00"
        case .transFluidTemp:
            return "19 40 49 00"
        case .engineOilTemp:
            return "11 54 64 00"
        case .transGear:
            return "19 9A 01 00"
        case .transSlipSpeed:
            return "19 92 64 00"
        }
    }

    private func handleMode1MockResponse(for command: OBDCommand.Mode1) -> String? {
        // 1. Check for fixed, static responses
        if let fixedResponse = MOCKComm.fixedMode1Responses[command] {
            return fixedResponse
        }

        // 2. Dispatch to smaller groups for dynamic responses
        if let response = mockMode1EngineAndFuelData(for: command) {
            return response
        }
        if let response = mockMode1O2AndEmissionsData(for: command) {
            return response
        }
        if let response = mockMode1ReadinessAndOtherData(for: command) {
            return response
        }

        // 3. If no specific mock is found
        obdDebug("No mock response for Mode 1 command: \(command)", category: .communication)
        return nil
    }

    private func handleMode6MockResponse(for command: OBDCommand.Mode6) -> String? {
        switch command {
        case .MIDS_A:
            return "00 C0 00 00 01 00"
        case .MIDS_B:
            return "02 C0 00 00 01 00"
        case .MIDS_C:
            return "04 C0 00 00 01 00"
        case .MIDS_D:
            return "06 C0 00 00 01 00"
        case .MIDS_E:
            return "08 C0 00 00 01 00"
        case .MIDS_F:
            return "0A C0 00 00 01 00"
        default:
            return nil
        }
    }

    private func handleMode9MockResponse(for command: OBDCommand.Mode9) -> String? {
        switch command {
        case .PIDS_9A:
            return "00 55 40 57 F0"
        case .VIN:
            return "02 01 31 4E 34 41 4C 33 41 50 37 44 43 31 39 39 35 38 33"
        default:
            return nil
        }
    }

    // MARK: - Individual Mode 1 PID Mock Generators

    // Dictionary for fixed Mode 1 responses
    private static let fixedMode1Responses: [OBDCommand.Mode1: String] = [
        .pidsA: "00 FF FF FF FF 00",
        .freezeDTC: "02 03 01",
        .airStatus: "12 04",
        .O2Sensor: "13 03",
        .O2Bank1Sensor3: "16 80 80",
        .O2Bank1Sensor4: "17 80 80",
        .O2Bank2Sensor3: "1A 80 80",
        .O2Bank2Sensor4: "1B 80 80",
        .obdcompliance: "1C 03",
        .O2SensorsALT: "1D 00",
        .auxInputStatus: "1E 00",
        .pidsB: "20 FF FF FF FF 00",
        .fuelRailPressureDirect: "23 02 BF",
        .pidsC: "40 FF FF FF FE 00",
        .controlModuleVoltage: "42 35 04",
        .ambientAirTemp: "46 32",
        .runTimeMIL: "4D 00 00",
        .maxValues: "4F FF FF FF FF FF",
        .fuelType: "51 01",
        .ethanoPercent: "52 1A", // 0x1A = 26% ethanol
        .emissionsReq: "5F 01",
    ]

    // MARK: - Grouped Mode 1 Dynamic PID Mock Generators

    private func mockMode1EngineAndFuelData(for command: OBDCommand.Mode1) -> String? {
        switch command {
        case .engineLoad:
            return mockEngineLoadResponse()
        case .coolantTemp:
            return mockTemperatureRampResponse(pid: "05", maxCelsius: 100.0)
        case .shortFuelTrim1:
            return mockFuelTrimResponse(pid: "06", waveform: .sine, frequency: 1.7, amplitude: 0.05)
        case .longFuelTrim1:
            return mockFuelTrimResponse(pid: "07", waveform: .sine, frequency: 0.2, amplitude: 0.02)
        case .shortFuelTrim2:
            return mockFuelTrimResponse(pid: "08", waveform: .cosine, frequency: 1.5, amplitude: 0.05)
        case .longFuelTrim2:
            return mockFuelTrimResponse(pid: "09", waveform: .cosine, frequency: 0.25, amplitude: 0.02)
        case .fuelPressure:
            return mockFuelPressureResponse()
        case .intakePressure:
            return mockIntakePressureResponse()
        case .rpm:
            return mockRPMResponse()
        case .speed:
            return mockSpeedResponse()
        case .timingAdvance:
            return mockTimingAdvanceResponse()
        case .intakeTemp:
            return mockTemperatureRampResponse(pid: "0F", maxCelsius: 70.0)
        case .maf:
            return mockMAFResponse()
        case .throttlePos:
            return mockThrottlePosResponse()
        case .fuelRailPressureVac:
            return mockFuelRailPressureVacResponse()
        case .absoluteLoad:
            return mockAbsoluteLoadResponse()
        case .relativeThrottlePos,
             .throttlePosB,
             .throttlePosC,
             .throttlePosD,
             .throttlePosE,
             .throttlePosF:
            return mockThrottlePositionSensorResponse(for: command)
        case .throttleActuator:
            return mockThrottleActuatorResponse()
        case .fuelRailPressureAbs:
            return mockFuelRailPressureAbsResponse()
        case .relativeAccelPos:
            return mockRelativeAccelPosResponse()
        case .engineOilTemp:
            return mockEngineOilTempResponse()
        case .fuelInjectionTiming:
            return mockFuelInjectionTimingResponse()
        case .fuelRate:
            return mockFuelRateResponse()
        default:
            return nil
        }
    }

    private func mockMode1O2AndEmissionsData(for command: OBDCommand.Mode1) -> String? {
        switch command {
        case .fuelStatus:
            return mockFuelStatusResponse()
        case .O2Bank1Sensor1:
            return mockO2SensorResponse(pid: "14", baseVoltage: 0.5, voltageSeed: 14, voltageScale: 0.3, trimSeed: 15, trimScale: 0.05)
        case .O2Bank1Sensor2:
            return mockO2SensorResponse(pid: "15", baseVoltage: 0.55, voltageSeed: 16, voltageScale: 0.25, trimSeed: 17, trimScale: 0.04)
        case .O2Bank2Sensor1:
            return mockO2SensorResponse(pid: "18", baseVoltage: 0.48, voltageSeed: 18, voltageScale: 0.28, trimSeed: 19, trimScale: 0.05)
        case .O2Bank2Sensor2:
            return mockO2SensorResponse(pid: "19", baseVoltage: 0.52, voltageSeed: 20, voltageScale: 0.22, trimSeed: 21, trimScale: 0.04)
        case .O2Sensor1WRVolatage,
             .O2Sensor2WRVolatage,
             .O2Sensor3WRVolatage,
             .O2Sensor4WRVolatage,
             .O2Sensor5WRVolatage,
             .O2Sensor6WRVolatage,
             .O2Sensor7WRVolatage,
             .O2Sensor8WRVolatage:
            return mockWidebandO2VoltageResponse(for: command)
        case .commandedEGR:
            return mockCommandedEGRResponse()
        case .EGRError:
            return mockEGRErrorResponse()
        case .evaporativePurge:
            return mockEvaporativePurgeResponse()
        case .evapVaporPressure:
            return mockEvapVaporPressureResponse()
        case .O2Sensor1WRCurrent,
             .O2Sensor2WRCurrent,
             .O2Sensor3WRCurrent,
             .O2Sensor4WRCurrent,
             .O2Sensor5WRCurrent,
             .O2Sensor6WRCurrent,
             .O2Sensor7WRCurrent,
             .O2Sensor8WRCurrent:
            return mockWidebandO2CurrentResponse(for: command)
        case .catalystTempB1S1,
             .catalystTempB2S1,
             .catalystTempB1S2,
             .catalystTempB2S2:
            return mockCatalystTemperatureResponse(for: command)
        case .commandedEquivRatio:
            return mockCommandedEquivRatioResponse()
        case .evapVaporPressureAbs:
            return mockSignedPressureResponse(pid: "53", baseline: 300, seed: 31, scale: 50.0)
        case .evapVaporPressureAlt:
            return mockSignedPressureResponse(pid: "54", baseline: 250, seed: 32, scale: 60.0)
        case .shortO2TrimB1:
            return mockCenteredTrimResponse(pid: "55", seed: 33, scale: 0.06)
        case .longO2TrimB1:
            return mockCenteredTrimResponse(pid: "56", seed: 34, scale: 0.03)
        case .shortO2TrimB2:
            return mockCenteredTrimResponse(pid: "57", seed: 35, scale: 0.06)
        case .longO2TrimB2:
            return mockCenteredTrimResponse(pid: "58", seed: 36, scale: 0.03)
        default:
            return nil
        }
    }

    private func mockMode1ReadinessAndOtherData(for command: OBDCommand.Mode1) -> String? {
        switch command {
        case .status:
            return mockStatusResponse()
        case .distanceWMIL:
            return mockAccumulatedDistanceResponse(pid: "21")
        case .warmUpsSinceDTCCleared:
            return mockWarmUpsSinceDTCClearedResponse()
        case .distanceSinceDTCCleared:
            return mockAccumulatedDistanceResponse(pid: "31")
        case .barometricPressure:
            return mockBarometricPressureResponse()
        case .statusDriveCycle:
            return mockStatusDriveCycleResponse()
        case .timeSinceDTCCleared:
            return mockTimeSinceDTCClearedResponse()
        case .maxMAF:
            return mockMaxMAFResponse()
        case .hybridBatteryLife:
            return mockHybridBatteryLifeResponse()
        default:
            return nil
        }
    }


    private func mockStatusResponse() -> String {
        // Progressive readiness over 2 minutes with gasoline monitors only
        let t = min(max(sessionElapsed(), 0.0), 120.0)
        let stages = Int(t / 12.0) // 10 stages (0...10)

        // Byte0: MIL on + 7 DTCs
        let milAndCountByte: UInt8 = 0x80 | 0x07 // 0x87

        // Base monitors in A (bit set = NOT ready). Start all not ready.
        // bit6 = Comprehensive, bit5 = Fuel System, bit4 = Misfire
        var baseMonitorByte: UInt8 = 0
        baseMonitorByte |= 0x40 // Comprehensive not ready
        baseMonitorByte |= 0x20 // Fuel System not ready
        baseMonitorByte |= 0x10 // Misfire not ready
        // Ensure diesel bit (0x08) is never set for gasoline

        // Extended monitors support (B): gasoline set
        // bit0 Catalyst, bit1 Heated Catalyst, bit2 Evap, bit3 Secondary Air,
        // bit5 O2 Sensor, bit6 O2 Heater, bit7 EGR/VVT
        var supportedMonitorByte: UInt8 = 0
        supportedMonitorByte |= 0x01 // Catalyst
        supportedMonitorByte |= 0x02 // Heated Catalyst
        supportedMonitorByte |= 0x04 // Evaporative System
        supportedMonitorByte |= 0x08 // Secondary Air
        supportedMonitorByte |= 0x20 // O2 Sensor
        supportedMonitorByte |= 0x40 // O2 Heater
        supportedMonitorByte |= 0x80 // EGR/VVT

        // Readiness C (1 = NOT ready, 0 = ready). Start all not ready for supported monitors.
        var readinessByte: UInt8 = 0
        readinessByte |= 0x01 // Catalyst not ready
        readinessByte |= 0x02 // Heated Catalyst not ready
        readinessByte |= 0x04 // Evap not ready
        readinessByte |= 0x08 // Secondary Air not ready
        readinessByte |= 0x20 // O2 Sensor not ready
        readinessByte |= 0x40 // O2 Heater not ready
        readinessByte |= 0x80 // EGR/VVT not ready

        // Define readiness order across 10 stages
        // 1) Comprehensive (A bit6), 2) Fuel (A bit5), 3) Misfire (A bit4),
        // 4) O2 Heater (C bit6), 5) O2 Sensor (C bit5), 6) Catalyst (C bit0),
        // 7) Evap (C bit2), 8) EGR (C bit7), 9) Secondary Air (C bit3), 10) Heated Catalyst (C bit1)
        if stages >= 1 { baseMonitorByte &= ~0x40 } // Comprehensive ready
        if stages >= 2 { baseMonitorByte &= ~0x20 } // Fuel ready
        if stages >= 3 { baseMonitorByte &= ~0x10 } // Misfire ready
        if stages >= 4 { readinessByte &= ~0x40 } // O2 Heater ready
        if stages >= 5 { readinessByte &= ~0x20 } // O2 Sensor ready
        if stages >= 6 { readinessByte &= ~0x01 } // Catalyst ready
        if stages >= 7 { readinessByte &= ~0x04 } // Evap ready
        if stages >= 8 { readinessByte &= ~0x80 } // EGR/VVT ready
        if stages >= 9 { readinessByte &= ~0x08 } // Secondary Air ready
        if stages >= 10 { readinessByte &= ~0x02 } // Heated Catalyst ready

        let payload = String(format: "01 %02X %02X %02X %02X", milAndCountByte, baseMonitorByte, supportedMonitorByte, readinessByte)
        return payload
    }

    private func mockFuelStatusResponse() -> String {
        let now = Date()
        if sessionState.testStart == nil { sessionState.testStart = now }
        let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)
        let warmupSeconds: TimeInterval = 60.0
        let clamped = max(0.0, min(warmupSeconds, elapsed))
        let tempC = (clamped / warmupSeconds) * 100.0

        let speed = currentMockSpeed(now: now)
        let rpm = currentMockRPM(fromSpeed: speed)
        let idleRpm: Double = 800.0
        let redlineRpm: Double = 8000.0
        let rpmN = max(0.0, min(1.0, (rpm - idleRpm) / (redlineRpm - idleRpm)))

        var demand = 0.15 + 0.45 * pow(rpmN, 2.0)
        demand += smoothNoise(seed: 5.5, scale: 0.015)

        var accel: Double = 0
        if let last = sessionState.lastTick {
            let dt = max(0.001, now.timeIntervalSince(last))
            let prevSpeed = currentMockSpeed(now: last)
            accel = (speed - prevSpeed) / dt
        }
        let isIdle = (rpm < 1100 && speed < 3)
        if isIdle {
            demand = max(demand, 0.06)
        }
        let isCoasting = (rpm > 1200 && accel < -4.0) && !isIdle
        if isCoasting {
            demand = min(demand, 0.03 + 0.03 * rpmN)
        }

        let throttlePct = demand * 100.0

        let warmThresholdC = 60.0
        let lowThrottleThresholdPct = 3.0

        let statusCode: UInt8
        if tempC < warmThresholdC {
            statusCode = 1
        } else if throttlePct < lowThrottleThresholdPct {
            statusCode = 3
        } else {
            statusCode = 2
        }

        let statusByte = statusCode
        return "03 " + String(format: "%02X %02X", statusByte, statusByte)
    }

    private func mockEngineLoadResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmClamped = min(8000.0, max(800.0, rpm))
        let throttleLike = ((rpmClamped - 800.0) / (8000.0 - 800.0))
        var load = throttleLike
        if speedValue >= 40 && speedValue <= 80 {
            let cruiseFactor = max(0.0, 1.0 - throttleLike * 1.4)
            load -= 0.20 * cruiseFactor
        }
        load += smoothNoise(seed: 4, scale: 0.03)
        load = max(0.0, min(1.0, load))
        let percent = UInt8(clamping: Int((load * 255.0).rounded()))
        return "04 " + String(format: "%02X", percent)
    }

    private func mockFuelPressureResponse() -> String {
        let centerKPa = 400.0 + smoothNoise(seed: 6, scale: 25.0)
        let kPa = max(200.0, min(600.0, centerKPa))
        let pressureByte = UInt8(max(0, min(255, Int((kPa / 3.0).rounded()))))
        return "0A " + String(format: "%02X", pressureByte)
    }

    private func mockIntakePressureResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
        var load = rpmN
        if speedValue >= 40 && speedValue <= 80 {
            let cruiseFactor = max(0.0, 1.0 - rpmN * 1.4)
            load -= 0.20 * cruiseFactor
        }
        load = max(0.0, min(1.0, load))
        var kPa = 25.0 + load * 70.0 + smoothNoise(seed: 8, scale: 2.0)
        kPa = max(20.0, min(100.0, kPa))
        let pressureByte = UInt8(max(0, min(255, Int(kPa.rounded()))))
        return "0B " + String(format: "%02X", pressureByte)
    }

    private func mockRPMResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpmDouble = currentMockRPM(fromSpeed: speedValue)
        let rpmClamped = min(8000.0, max(800.0, rpmDouble))
        let raw = Int(rpmClamped.rounded()) * 4
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "0C " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockSpeedResponse() -> String {
        let speedValue = currentMockSpeed()
        let clamped = max(0.0, min(255.0, speedValue))
        let hexSpeed = String(format: "%02X", Int(clamped.rounded()))
        return "0D " + hexSpeed
    }

    private func mockTimingAdvanceResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (6000.0 - 800.0)))

        var load = rpmN
        if speedValue >= 40 && speedValue <= 80 {
            let cruiseFactor = max(0.0, 1.0 - rpmN * 1.2)
            load -= 0.25 * cruiseFactor
        }
        load = max(0.0, min(1.0, load))

        var advance = 10.0 + (rpmN * 25.0) - (load * 12.0)
        advance += smoothNoise(seed: 7, scale: 1.0)
        advance = max(2.0, min(45.0, advance))

        let raw = max(0, min(255, Int((advance + 64.0) * 2.0)))
        let timingByte = UInt8(raw)

        return "0E " + String(format: "%02X", timingByte)
    }

    private func mockMAFResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
        let base = 2.0 + rpmN * 118.0
        let withLoad = base * (0.8 + 0.4 * rpmN)
        let mafGs = max(2.0, min(200.0, withLoad + smoothNoise(seed: 2, scale: 3.0)))
        let raw = Int((mafGs * 100.0).rounded())
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "10 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockThrottlePosResponse() -> String {
        let now = Date()
        let speed = currentMockSpeed(now: now)
        let rpm = currentMockRPM(fromSpeed: speed)
        let idleRpm: Double = 800.0
        let redlineRpm: Double = 8000.0
        let rpmN = max(0.0, min(1.0, (rpm - idleRpm) / (redlineRpm - idleRpm)))

        var demand = 0.15 + 0.45 * pow(rpmN, 2.0)
        demand += 0.10 * sin(sessionElapsed() * 0.15)
        demand += 0.05 * sin(sessionElapsed() * 0.50 + 1.2)

        var accel: Double = 0
        if let last = sessionState.lastTick {
            let dt = max(0.001, now.timeIntervalSince(last))
            let prevSpeed = currentMockSpeed(now: last)
            accel = (speed - prevSpeed) / dt
        }

        let positiveAccelBias = max(0.0, min(0.35, accel * 0.025))
        let negativeAccelBias = max(-0.50, min(0.0, accel * 0.05))
        demand += positiveAccelBias + negativeAccelBias

        let isIdle = (rpm < 1100 && speed < 3)
        if isIdle {
            demand = max(demand, 0.06 + 0.01 * sin(sessionElapsed() * 1.5))
        }
        let isCoasting = (rpm > 1200 && accel < -4.0)
        if isCoasting && !isIdle {
            demand = min(demand, 0.02 + 0.03 * rpmN)
        }

        let isHighLoad = (rpmN > 0.85) || (accel > 5.0)
        if isHighLoad {
            let wotFloor = 0.75
            let wotCeiling = 0.99
            let scaledRpmTarget = wotFloor + (wotCeiling - wotFloor) * min(1.0, (rpmN - 0.8) / 0.2)
            demand = max(demand, scaledRpmTarget)
        }

        demand += smoothNoise(seed: 5.5, scale: 0.015)
        demand = max(0.0, min(1.0, demand))

        let throttleByte = UInt8(clamping: Int((demand * 255.0).rounded()))
        return "11 " + String(format: "%02X", throttleByte)
    }

    private func mockRunTimeResponse() -> String {
        _ = sessionElapsed()
        let seconds = Int(sessionState.accumulatedSeconds.rounded())
        let raw = max(0, min(65535, seconds))
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "1F " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockFuelRailPressureVacResponse() -> String {
        let speed = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speed)
        let load = max(0.0, min(1.0, (rpm - 800.0) / (6000.0 - 800.0)))

        let kPa = 300.0 + (load * 100.0) + smoothNoise(seed: 22, scale: 10.0)
        let raw = Int((kPa / 10.0).rounded())
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "22 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockWidebandO2VoltageResponse(for command: OBDCommand.Mode1) -> String {
        let baseMv = 2500.0 + smoothNoise(seed: 23, scale: 200.0) * 1000.0
        let raw = max(0, min(8192, Int(baseMv / 1.0)))
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return String(format: "%02X %02X %02X %02X %02X",
                      pidByte(for: command),
                      highByte, lowByte, 0x80, 0x00)
    }

    private func mockCommandedEGRResponse() -> String {
        let pct = UInt8(clamping: Int((max(0.0, min(1.0, 0.2 + 0.2 * sin(sessionElapsed() * 0.3))) * 255.0).rounded()))
        return "2C " + String(format: "%02X 00 00", pct)
    }

    private func mockEGRErrorResponse() -> String {
        let centered = 128 + Int((smoothNoise(seed: 24, scale: 0.05) * 255.0))
        let errorByte = UInt8(clamping: centered)
        return "2D " + String(format: "%02X 00 00", errorByte)
    }

    private func mockEvaporativePurgeResponse() -> String {
        let pct = UInt8(clamping: Int((max(0.0, min(1.0, 0.1 + 0.3 * sin(sessionElapsed() * 0.2))) * 255.0).rounded()))
        return "2E " + String(format: "%02X 00 00", pct)
    }

    private func mockFuelLevelResponse() -> String {
        let now = Date()
        if sessionState.testStart == nil {
            sessionState.testStart = now
        }
        let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)
        let drained = Int(elapsed / 10.0)
        let fuelPercent = max(0, 90 - drained)
        let byte = UInt8(max(0, min(255, Int((Double(fuelPercent) * 255.0 / 100.0).rounded()))))
        return "2F " + String(format: "%02X 00 00", byte)
    }

    private func mockWarmUpsSinceDTCClearedResponse() -> String {
        let cycles = min(40, Int(sessionElapsed() / 300.0))
        return "30 " + String(format: "00 00 %02X", cycles)
    }

    private func mockEvapVaporPressureResponse() -> String {
        let pa = Int(100 + smoothNoise(seed: 25, scale: 50.0) * 100.0)
        let raw = UInt16(bitPattern: Int16(clamping: pa))
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = Int(raw & 0xFF)
        return "32 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockBarometricPressureResponse() -> String {
        var kPa = 101.0 + smoothNoise(seed: 9, scale: 0.6)
        kPa = max(95.0, min(105.0, kPa))
        let pressureByte = UInt8(max(0, min(255, Int(kPa.rounded()))))
        return "33 " + String(format: "%02X", pressureByte)
    }

    private func mockWidebandO2CurrentResponse(for command: OBDCommand.Mode1) -> String {
        let oscillation = sin(sessionElapsed() * 1.5) * 20.0
        let noise = smoothNoise(seed: 26, scale: 2.0)
        let rawA = UInt8(clamping: Int(128 + oscillation + noise))
        return String(format: "%02X %02X %02X",
                      pidByte(for: command),
                      rawA, 0x00)
    }

    private func mockCatalystTemperatureResponse(for command: OBDCommand.Mode1) -> String {
        let tC = 300.0 + 250.0 * (0.5 + 0.5 * sin(sessionElapsed() * 0.1)) + smoothNoise(seed: 27, scale: 15.0)
        let raw = Int(((tC + 40.0) * 10.0).rounded())
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return String(format: "%02X %02X",
                      pidByte(for: command),
                      highByte, lowByte)
    }

    private func mockStatusDriveCycleResponse() -> String {
        let t = min(max(sessionElapsed(), 0.0), 120.0)
        let stages = Int(t / 12.0)

        let milAndCountByte: UInt8 = 0x80 | 0x07

        var baseMonitorByte: UInt8 = 0
        baseMonitorByte |= 0x40
        baseMonitorByte |= 0x20
        baseMonitorByte |= 0x10

        var supportedMonitorByte: UInt8 = 0
        supportedMonitorByte |= 0x01
        supportedMonitorByte |= 0x02
        supportedMonitorByte |= 0x04
        supportedMonitorByte |= 0x08
        supportedMonitorByte |= 0x20
        supportedMonitorByte |= 0x40
        supportedMonitorByte |= 0x80

        var readinessByte: UInt8 = 0
        readinessByte |= 0x01
        readinessByte |= 0x02
        readinessByte |= 0x04
        readinessByte |= 0x08
        readinessByte |= 0x20
        readinessByte |= 0x40
        readinessByte |= 0x80

        if stages >= 1 { baseMonitorByte &= ~0x40 }
        if stages >= 2 { baseMonitorByte &= ~0x20 }
        if stages >= 3 { baseMonitorByte &= ~0x10 }
        if stages >= 4 { readinessByte &= ~0x40 }
        if stages >= 5 { readinessByte &= ~0x20 }
        if stages >= 6 { readinessByte &= ~0x01 }
        if stages >= 7 { readinessByte &= ~0x04 }
        if stages >= 8 { readinessByte &= ~0x80 }
        if stages >= 9 { readinessByte &= ~0x08 }
        if stages >= 10 { readinessByte &= ~0x02 }

        let payload = String(format: "41 %02X %02X %02X %02X", milAndCountByte, baseMonitorByte, supportedMonitorByte, readinessByte)
        return payload
    }

    private func mockAbsoluteLoadResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
        var load = 0.1 + 0.8 * rpmN
        load += smoothNoise(seed: 28, scale: 0.05)
        load = max(0.0, min(1.0, load))
        let raw = UInt16(clamping: Int((load * 65535.0).rounded()))
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = Int(raw & 0xFF)
        return "43 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockCommandedEquivRatioResponse() -> String {
        let lambda = 1.0 + smoothNoise(seed: 29, scale: 0.03)
        let raw = UInt16(clamping: Int((lambda * 32768.0).rounded()))
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = Int(raw & 0xFF)
        return "44 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockThrottlePositionSensorResponse(for command: OBDCommand.Mode1) -> String {
        let base = 0.2 + 0.4 * (0.5 + 0.5 * sin(sessionElapsed() * 0.3))
        let offset = smoothNoise(seed: 30, scale: 0.03)
        let pct = UInt8(clamping: Int((max(0.0, min(1.0, base + offset)) * 255.0).rounded()))
        return String(format: "%02X %02X 00",
                      pidByte(for: command),
                      pct)
    }

    private func mockThrottleActuatorResponse() -> String {
        let pct = UInt8(clamping: Int((max(0.0, min(1.0, 0.25 + 0.5 * sin(sessionElapsed() * 0.22))) * 255.0).rounded()))
        return "4C " + String(format: "%02X 00", pct)
    }

    private func mockTimeSinceDTCClearedResponse() -> String {
        let seconds = Int(sessionElapsed().rounded())
        let raw = UInt16(clamping: seconds)
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = raw & 0xFF
        return "4E " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockMaxMAFResponse() -> String {
        let maxMafGs = 300.0
        let raw = UInt16(clamping: Int((maxMafGs * 50.0).rounded()))
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "50 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockFuelRailPressureAbsResponse() -> String {
        let kPa = 400.0 + smoothNoise(seed: 37, scale: 40.0)
        let raw = UInt16(clamping: Int((kPa / 10.0).rounded()))
        let highByte = Int((raw >> 8) & 0xFF)
        let lowByte = Int(raw & 0xFF)
        return "59 " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockRelativeAccelPosResponse() -> String {
        let pct = UInt8(clamping: Int((max(0.0, min(1.0, 0.1 + 0.8 * (0.5 + 0.5 * sin(sessionElapsed() * 0.4)))) * 255.0).rounded()))
        return "5A " + String(format: "%02X", pct)
    }

    private func mockHybridBatteryLifeResponse() -> String {
        let decline = sessionElapsed() / 600.0
        let percent = max(50.0, 90.0 - decline)
        let raw = max(0, min(65535, Int((percent / 100.0) * 65535.0)))
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "5B " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockEngineOilTempResponse() -> String {
        let t = sessionElapsed()
        let target = 100.0
        let ambient = 20.0
        let temp = ambient + (target - ambient) * (1.0 - exp(-t / 900.0)) + smoothNoise(seed: 11, scale: 1.5)
        let clamped = max(-40.0, min(150.0, temp))
        let rawA = UInt8(max(0, min(255, Int((clamped + 40.0).rounded()))))
        return "5C " + String(format: "%02X", rawA)
    }

    private func mockFuelInjectionTimingResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
        let load = rpmN

        var deg = 5.0 + 15.0 * (1.0 - load) - 2.5 * rpmN
        deg += smoothNoise(seed: 12, scale: 0.8)
        deg = max(-5.0, min(25.0, deg))

        let raw = Int((deg * 10.0) + 21000.0)
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF

        return "5D " + String(format: "%02X %02X", highByte, lowByte)
    }

    private func mockFuelRateResponse() -> String {
        let speedValue = currentMockSpeed()
        let rpm = currentMockRPM(fromSpeed: speedValue)
        let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
        let load = rpmN
        var lph = 1.2 + 18.0 * load + 10.0 * rpmN + smoothNoise(seed: 13, scale: 0.8)
        lph = max(0.5, min(60.0, lph))
        let raw = Int((lph * 20.0).rounded())
        let highByte = (raw >> 8) & 0xFF
        let lowByte = raw & 0xFF
        return "5E " + String(format: "%02X %02X", highByte, lowByte)
    }

    // Handles the raw-text mock path used in the final else-branch of sendCommand
    func makeRawMockResponse(for command: String) -> String? {
        if let payload = makeMockResponse(for: command) {
            return payload
        }
        return nil
    }

    // Helper to get PID byte for a Mode1 case (for grouped handling above)
    func pidByte(for mode1: OBDCommand.Mode1) -> UInt8 {
        let hex = mode1.properties.command.dropFirst(2) // drop "01"
        let pidHex = String(hex)
        return UInt8(pidHex, radix: 16) ?? 0x00
    }

  
}

extension String {
    func chunked(by chunkSize: Int) -> Array<String> {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            String(self[self.index(self.startIndex, offsetBy: $0)..<self.index(self.startIndex, offsetBy: min($0 + chunkSize, self.count))])
        }
    }
}
