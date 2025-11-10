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

    func sendCommand(_ command: String, retries: Int = 3) async throws -> [String] {
        obdInfo("Sending command: \(command)")
        var header = ""

        let prefix = String(command.prefix(2))
        if prefix == "01" || prefix == "06" || prefix == "09" {
            var response: String = ""
            if ecuSettings.headerOn {
                header = "7E8"
            }
            for i in stride(from: 2, to: command.count, by: 2) {
                let index = command.index(command.startIndex, offsetBy: i)
                let nextIndex = command.index(command.startIndex, offsetBy: i + 2)
                let subCommand = prefix + String(command[index..<nextIndex])
                guard let value = makeMockResponse(for: subCommand) else {
                    return ["No Data"]

                }
                response.append(value + " ")
            }
            guard var mode = Int(command.prefix(2)) else {
                return [""]
            }
            mode = mode + 40

            if response.count > 18 {
                var chunks = response.chunked(by: 15)

                var ff = chunks[0]

                var Totallength = 0

                let ffLength = ff.replacingOccurrences(of: " ", with: "").count / 2

                Totallength += ffLength

                var cf = Array(chunks.dropFirst())
                Totallength += cf.joined().replacingOccurrences(of: " ", with: "").count

                var lengthHex = String(format: "%02X", Totallength - 1)

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
                        if let _ = UInt8(hexByte, radix: 16) {
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
            // 03 is a request for DTCs
            let dtcs = ["P0104", "U0207"]
            var response = ""
            for dtc in dtcs {
                var hexString = String(dtc.suffix(4))
                hexString = hexString.chunked(by: 2).joined(separator: " ")
                response +=  hexString
                obdDebug("Generated DTC hex: \(hexString)", category: .communication)
            }
            var header = ""
            if ecuSettings.headerOn {
                header = "7E8"
            }
            let mode = "43"
            response = mode + " " + response
            let length = String(format: "%02X", response.count / 3 + 1)
            response = header + " " + length + " " + response
            while response.count < 26 {
                response.append(" 00")
            }
            return [response]
        } else {
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

    func connectAsync(timeout: TimeInterval, peripheral: CBPeripheral? = nil) async throws {
        connectionState = .connectedToAdapter
        obdDelegate?.connectionStateChanged(state: .connectedToAdapter)
    }

    func scanForPeripherals() async throws {

    }
}

// MARK: - Per-session mock generation (moved from OBDCommand extension)

private extension MOCKComm {
    // Session time helpers
    func sessionElapsed(now: Date = Date()) -> Double {
        if sessionState.testStart == nil {
            sessionState.testStart = now
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

    // Generates the per-PID payload (no header/length/service), similar to the old OBDCommand.mockResponse
    func makeMockResponse(for command: String) -> String? {
        guard let obd2Command = OBDCommand.from(command: command) else {
            obdWarning("Invalid mock command: \(command)", category: .communication)
            return "Invalid command"
        }

        switch obd2Command {
        case .mode1(let command):
            switch command {
            case .pidsA:
                return "00 BE 3F A8 13 00"
            case .status:
                return "01 00 07 E5 00"
            case .pidsB:
                return "20 90 07 E0 11 00"
            case .pidsC:
                return "40 FA DC 80 00 00"
            case .controlModuleVoltage:
                return "42 35 04"
            case .fuelStatus:
                return "03 02 04"
            case .rpm:
                let speedValue = currentMockSpeed()
                let rpmDouble = currentMockRPM(fromSpeed: speedValue)
                let rpmClamped = min(8000.0, max(800.0, rpmDouble))
                let raw = Int(rpmClamped.rounded()) * 4 // OBD-II encoding for RPM
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "0C" + " " + hexA + " " + hexB
            case .speed:
                let speedValue = currentMockSpeed()
                let clamped = max(0.0, min(255.0, speedValue))
                let hexSpeed = String(format: "%02X", Int(clamped.rounded()))
                return "0D" + " " + hexSpeed
            case .coolantTemp:
                // Ramp from 0 to 100°C over 60 seconds.
                let now = Date()
                if sessionState.testStart == nil {
                    sessionState.testStart = now
                }
                let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)
                let clamped = max(0.0, min(60.0, elapsed))
                let tempC = Int((clamped / 60.0) * 100.0) // 0…100
                // OBD-II PID 0105 encoding: A = tempC + 40
                let rawA = UInt8(max(0, min(140, tempC + 40)))
                let hexTemp = String(format: "%02X", rawA)
                return "05" + " " + hexTemp
            case .maf:
                // Approximate MAF (g/s) from RPM and a mild speed factor
                // Normalize RPM 800..8000 to 0..1
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                // Base 2..120 g/s scaled by rpm and load-ish term
                let base = 2.0 + rpmN * 118.0
                let withLoad = base * (0.8 + 0.4 * rpmN)
                let mafGs = max(2.0, min(200.0, withLoad + smoothNoise(seed: 2, scale: 3.0)))
                // Encode: value = (256*A + B)/100 g/s → raw = Int(mafGs * 100)
                let raw = Int((mafGs * 100.0).rounded())
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "10" + " " + hexA + " " + hexB
            case .engineLoad:
                // More realistic engine load modeled from RPM and throttle-like demand
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmClamped = min(8000.0, max(800.0, rpm))
                let throttleLike = ((rpmClamped - 800.0) / (8000.0 - 800.0)) // 0.0 … 1.0
                var load = throttleLike
                if speedValue >= 40 && speedValue <= 80 {
                    let cruiseFactor = max(0.0, 1.0 - throttleLike * 1.4)
                    load -= 0.20 * cruiseFactor
                }
                if speedValue < 2 && rpmClamped < 1200 {
                    load = max(load, 0.08 + smoothNoise(seed: 3, scale: 0.02))
                }
                load += smoothNoise(seed: 4, scale: 0.03)
                load = max(0.0, min(1.0, load))
                let percent = Int((load * 100.0).rounded())
                let A = UInt8(max(0, min(255, Int((Double(percent) * 255.0 / 100.0).rounded()))))
                let hexA = String(format: "%02X", A)
                return "04" + " " + hexA
            case .throttlePos:
                let speedValue = currentMockSpeed()
                let rpmDouble = currentMockRPM(fromSpeed: speedValue)
                let rpmClamped = min(8000.0, max(800.0, rpmDouble))
                var throttle = ((rpmClamped - 800.0) / (8000.0 - 800.0)) * 100.0
                throttle += smoothNoise(seed: 5, scale: 3.0)
                let throttleByte = UInt8(max(0, min(100, Int(throttle.rounded()))))
                let hexPos = String(format: "%02X", throttleByte)
                return "11" + " " + hexPos
            case .fuelLevel:
                // Start at 90% and decrease over time (1% every 10 seconds) until 0%.
                let now = Date()
                if sessionState.testStart == nil {
                    sessionState.testStart = now
                }
                let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)
                let drained = Int(elapsed / 10.0) // 1% per 10s
                let fuelPercent = max(0, 90 - drained)
                let byte = UInt8(max(0, min(255, Int((Double(fuelPercent) * 255.0 / 100.0).rounded()))))
                let hexLevel = String(format: "%02X", byte)
                return "2F" + " " + hexLevel
            case .fuelPressure:
                // Gentle drift around 400 kPa (encoded spec: A*3 = kPa)
                let centerKPa = 400.0 + smoothNoise(seed: 6, scale: 25.0)
                let kPa = max(200.0, min(600.0, centerKPa))
                let A = UInt8(max(0, min(255, Int((kPa / 3.0).rounded()))))
                let hexA = String(format: "%02X", A)
                return "0A" + " " + hexA
            case .intakeTemp:
                let now = Date()
                if sessionState.testStart == nil {
                    sessionState.testStart = now
                }
                let elapsed = now.timeIntervalSince(sessionState.testStart ?? now)
                let clamped = max(0.0, min(60.0, elapsed))
                let tempC = Int((clamped / 60.0) * 70.0) // 0…70
                let rawA = UInt8(max(0, min(140, tempC + 40)))
                let hexTemp = String(format: "%02X", rawA)
                return "0F" + " " + hexTemp
            case .timingAdvance:
                // Positive at light load and moderate RPM, retards with high load
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                // Reuse load logic lightly
                var load = rpmN
                if speedValue >= 40 && speedValue <= 80 {
                    let cruiseFactor = max(0.0, 1.0 - rpmN * 1.4)
                    load -= 0.20 * cruiseFactor
                }
                load = max(0.0, min(1.0, load))
                // Base advance 10° at light load, drop toward -5° at high load/high rpm
                var advance = 15.0 * (1.0 - load) - 5.0 * rpmN
                advance += smoothNoise(seed: 7, scale: 1.0)
                // Encode: A = (advance*2)+64 (per decoder expectation)
                let raw = Int((advance * 2.0).rounded()) + 64
                let A = UInt8(max(0, min(255, raw)))
                let hexA = String(format: "%02X", A)
                return "0E" + " " + hexA
            case .intakePressure:
                // Lower under vacuum (idle/cruise), higher near WOT
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                var load = rpmN
                if speedValue >= 40 && speedValue <= 80 {
                    let cruiseFactor = max(0.0, 1.0 - rpmN * 1.4)
                    load -= 0.20 * cruiseFactor
                }
                load = max(0.0, min(1.0, load))
                // Map load to 25..95 kPa with small noise
                var kPa = 25.0 + load * 70.0 + smoothNoise(seed: 8, scale: 2.0)
                kPa = max(20.0, min(100.0, kPa))
                let A = UInt8(max(0, min(255, Int(kPa.rounded()))))
                let hexA = String(format: "%02X", A)
                return "0B" + " " + hexA
            case .barometricPressure:
                // Nearly constant (simulate altitude ~101 kPa) with tiny sensor noise
                var kPa = 101.0 + smoothNoise(seed: 9, scale: 0.6)
                kPa = max(95.0, min(105.0, kPa))
                let A = UInt8(max(0, min(255, Int(kPa.rounded()))))
                let hexA = String(format: "%02X", A)
                return "33" + " " + hexA
            case .fuelType:
                return "01 01"
            case .fuelRailPressureDirect:
                // Scale with load and RPM; encode as 10 kPa units via (A*256+B)*10 kPa
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                let load = rpmN
                var kPa = 5000.0 + load * 12000.0 + smoothNoise(seed: 10, scale: 200.0)
                kPa = max(3000.0, min(20000.0, kPa))
                let raw = Int((kPa / 10.0).rounded())
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "23" + " " + hexA + " " + hexB
            case .ethanoPercent:
                // Fixed blend (e.g., E10 ~ 10%)
                let A = UInt8(26) // ~10% of 255
                let hexA = String(format: "%02X", A)
                return "52" + " " + hexA
            case .engineOilTemp:
                // Rise from ambient 20°C toward 100°C over ~15 minutes with small noise
                let t = sessionElapsed()
                let target = 100.0
                let ambient = 20.0
                let temp = ambient + (target - ambient) * (1.0 - exp(-t / 900.0)) + smoothNoise(seed: 11, scale: 1.5)
                let clamped = max(-40.0, min(150.0, temp))
                let rawA = UInt8(max(0, min(255, Int((clamped + 40.0).rounded()))))
                let hexA = String(format: "%02X", rawA)
                return "5C" + " " + hexA
            case .fuelInjectionTiming:
                // Signed degrees BTDC/ATDC; tie to load and RPM
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                let load = rpmN
                var deg = 5.0 + 10.0 * (1.0 - load) - 6.0 * rpmN + smoothNoise(seed: 12, scale: 1.0) // +/- range
                deg = max(-20.0, min(25.0, deg))
                // Encode per typical: value = ((A*256)+B)/128 - 210 (depends on decoder; here use uas(0x1B) style 0.01?)
                // We’ll map to 0.1° resolution: raw = (deg + 210) * 10
                let raw = Int(((deg + 210.0) * 10.0).rounded())
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "5D" + " " + hexA + " " + hexB
            case .fuelRate:
                // L/h roughly proportional to load and RPM
                let speedValue = currentMockSpeed()
                let rpm = currentMockRPM(fromSpeed: speedValue)
                let rpmN = max(0.0, min(1.0, (rpm - 800.0) / (8000.0 - 800.0)))
                let load = rpmN
                var lph = 1.2 + 18.0 * load + 10.0 * rpmN + smoothNoise(seed: 13, scale: 0.8)
                lph = max(0.5, min(60.0, lph))
                // Encode: value = ((A*256)+B)/20 → raw = lph*20
                let raw = Int((lph * 20.0).rounded())
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "5E" + " " + hexA + " " + hexB
            case .emissionsReq:
                return "01 01"
            case .runTime:
                // Seconds since session start
                _ = sessionElapsed()
                let seconds = Int(sessionState.accumulatedSeconds.rounded())
                let raw = max(0, min(65535, seconds))
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "1F" + " " + hexA + " " + hexB
            case .distanceSinceDTCCleared:
                // Integrate distance; encode in km
                _ = sessionElapsed()
                let km = sessionState.accumulatedMeters / 1000.0
                let raw = max(0, min(65535, Int(km.rounded())))
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "31" + " " + hexA + " " + hexB
            case .distanceWMIL:
                // Mirror distance since start as well
                _ = sessionElapsed()
                let km = sessionState.accumulatedMeters / 1000.0
                let raw = max(0, min(65535, Int(km.rounded())))
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "21" + " " + hexA + " " + hexB
            case .warmUpsSinceDTCCleared:
                // Slow increase every ~5 minutes up to 40
                let cycles = min(40, Int(sessionElapsed() / 300.0))
                let hexWarmUp = String(format: "%02X", cycles)
                return "30" + " 00 00 " + hexWarmUp
            case .hybridBatteryLife:
                // Slow decline from 90% by 0.1% per minute
                let decline = sessionElapsed() / 600.0
                let percent = max(50.0, 90.0 - decline)
                let raw = max(0, min(65535, Int((percent / 100.0) * 65535.0)))
                let A = (raw >> 8) & 0xFF
                let B = raw & 0xFF
                let hexA = String(format: "%02X", A)
                let hexB = String(format: "%02X", B)
                return "5B" + " " + hexA + " " + hexB
            default:
                return nil
            }

        case .mode6(let command):
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

        case .mode9(let command):
            switch command {
            case .PIDS_9A:
                return "00 55 40 57 F0"
            case .VIN:
                return "02 01 31 4E 34 41 4C 33 41 50 37 44 43 31 39 39 35 38 33"
            default:
                return nil
            }

        default:
            obdDebug("No mock response for command: \(command)", category: .communication)
            return nil
        }
    }

    // Handles the raw-text mock path used in the final else-branch of sendCommand
    func makeRawMockResponse(for command: String) -> String? {
        // Reuse makeMockResponse when possible; otherwise emulate a simple echo format
        if let payload = makeMockResponse(for: command) {
            return payload
        }
        return nil
    }
}

//        case .O902: return  "10 14 49 02 01 31 4E 34 \r\n"
//            + header + "21 41 4C 33 41 50 37 44 \r\n" + header + "22 43 31 39 39 35 38 33 \r\n\r\n>"
extension String {
    func chunked(by chunkSize: Int) -> Array<String> {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            String(self[self.index(self.startIndex, offsetBy: $0)..<self.index(self.startIndex, offsetBy: min($0 + chunkSize, self.count))])
        }
    }
}
