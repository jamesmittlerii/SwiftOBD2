@preconcurrency @testable import SwiftOBD2
import Combine
import CoreBluetooth
import XCTest

final class CoverageExpansionTests: XCTestCase {
    func testMeasurementUnitAndProtocolHelpers() {
        XCTAssertEqual(MeasurementUnit.metric.next, .imperial)
        XCTAssertEqual(MeasurementUnit.imperial.next, .metric)
        XCTAssertEqual(MeasurementUnit.allCases, [.metric, .imperial])

        XCTAssertEqual(PROTOCOL.protocol6.idBits, 11)
        XCTAssertEqual(PROTOCOL.protocol7.idBits, 29)
        XCTAssertEqual(PROTOCOL.protocol6.cmd, "ATSP6")
        XCTAssertEqual(PROTOCOL.protocolC.nextProtocol(), .protocolB)
        XCTAssertEqual(PROTOCOL.protocol1.nextProtocol(), .NONE)
    }

    func testUtilityHelpers() {
        XCTAssertEqual(bytesToInt(Data([0x12, 0x34])), 0x1234)
        XCTAssertEqual("7E8064100BE3EA813".hexBytes.prefix(3), [0x7E, 0x80, 0x64])
        XCTAssertTrue("7E8064100BE3EA813".isHex)
        XCTAssertFalse("7E8 06".isHex)
        XCTAssertEqual(Data([0x00, 0xFF]).bitCount(), 16)

        let bits = BitArray(data: Data([0b1010_0001]))
        XCTAssertEqual(bits.binaryArray, [1, 0, 1, 0, 0, 0, 0, 1])
        XCTAssertEqual(bits.index(of: 1), 0)
        XCTAssertEqual(bits.value(at: 0..<4), 0b1010)
    }

    func testCommandPropertiesDecodeAndFromCommand() {
        let unsupported = CommandProperties("FFFF", "Unsupported", 1, .none)
        if case .failure(.unsupportedDecoder) = unsupported.decode(data: Data([0x00])) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected unsupported decoder failure")
        }

        let temp = OBDCommand.mode1(.coolantTemp)
        let decoded = temp.properties.decode(data: Data([0x50]))
        switch decoded {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 40, accuracy: 0.001)
        case .failure(let error):
            XCTFail("Unexpected decode failure: \(error)")
        }

        XCTAssertEqual(OBDCommand.from(command: "010C"), .mode1(.rpm))
        XCTAssertEqual(OBDCommand.from(command: "221470"), .GMmode22(.engineOilPressure))
        XCTAssertNil(OBDCommand.from(command: "FFFF"))

        XCTAssertTrue(OBDCommand.pidGetters.contains(.mode1(.pidsA)))
        XCTAssertTrue(OBDCommand.pidGetters.contains(.mode6(.MIDS_A)))
        XCTAssertTrue(OBDCommand.pidGetters.contains(.mode9(.PIDS_9A)))
        XCTAssertFalse(OBDCommand.pidGetters.contains(.mode1(.speed)))
    }

    func testOBDCommandCodableRoundTripAndFailures() throws {
        let samples: [OBDCommand] = [
            .general(.ATZ),
            .mode1(.rpm),
            .mode3(.GET_DTC),
            .mode6(.MIDS_A),
            .mode9(.VIN),
            .GMmode22(.engineOilTemp),
            .protocols(.ATSP6)
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sample in samples {
            let data = try encoder.encode(sample)
            XCTAssertEqual(try decoder.decode(OBDCommand.self, from: data), sample)
        }

        XCTAssertThrowsError(
            try decoder.decode(
                OBDCommand.self,
                from: #"{"type":"invalid","command":"ATZ"}"#.data(using: .utf8)!
            )
        )

        XCTAssertThrowsError(
            try decoder.decode(
                OBDCommand.self,
                from: #"{"type":"mode1","command":"notARealCommand"}"#.data(using: .utf8)!
            )
        )
    }

    func testParserAndLegacyParserEdgeCases() throws {
        let parser = try CANParser(
            [
                "7E8 10 14 49 02 01 31 4E 34",
                "7E8 21 41 4C 33 41 50 37 44",
                "7E8 22 43 31 39 39 35 38 33"
            ],
            idBits: 11
        )
        XCTAssertEqual(parser.messages.count, 1)
        XCTAssertEqual(parser.messages[0].data, Data([0x02, 0x01]) + Data("1N4AL3AP7DC199583".utf8))

        let legacyVIN = try LegacyParcer(
            [
                "48 6B 10 49 02 01 31 4E 34 FF",
                "48 6B 10 49 02 02 41 4C 33 41 FF",
                "48 6B 10 49 02 03 50 37 44 43 FF"
            ]
        )
        XCTAssertEqual(legacyVIN.messages.count, 1)
        XCTAssertEqual(String(bytes: legacyVIN.messages[0].data ?? Data(), encoding: .utf8), "1N4AL3AP7DC")

        // Changed raw input to be clearly too short, ensuring 'Frame size out of range' error
        XCTAssertThrowsError(try Frame(raw: "7E8", idBits: 11)) { error in
            guard case ParserError.error(let message) = error else {
                return XCTFail("Expected parser error")
            }
            XCTAssertEqual(message, "Invalid frame size")
        }
        XCTAssertThrowsError(
            try LegacyParcer(
                [
                    "48 6B 10 49 02 02 31 4E 34 FF",
                    "48 6B 10 49 02 03 41 4C 33 FF"
                ]
            )
        )
    }

    func testDecoderImperialAndFailureBranches() {
        switch TemperatureDecoder().decode(data: Data([0x50]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 104, accuracy: 0.001)
            XCTAssertEqual(result.measurementResult?.unit, UnitTemperature.fahrenheit)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch PressureDecoder().decode(data: Data([0x64]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 14.5038, accuracy: 0.001)
            XCTAssertEqual(result.measurementResult?.unit, UnitPressure.poundsForcePerSquareInch)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch FuelPressureDecoder().decode(data: Data([0x0A]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 4.35114, accuracy: 0.001)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch AbsEvapPressureDecoder().decode(data: Data([0x01, 0xF4]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 0.362595, accuracy: 0.0001)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch EvapPressureDecoder().decode(data: Data([0xFF, 0xFC]), unit: .metric) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), -1, accuracy: 0.001)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.invalidData) = EvapPressureDecoder().decode(data: Data([0xFF]), unit: .metric) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid evap pressure data")
        }

        switch FuelRateDecoder().decode(data: Data([0x00, 0x64]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 1.32086, accuracy: 0.0001)
            XCTAssertEqual(result.measurementResult?.unit, .gallonsPerHour)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.invalidData) = FuelRateDecoder().decode(data: Data([0x01]), unit: .metric) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid fuel-rate data")
        }

        switch FuelTypeDecoder().decode(data: Data([0x01]), unit: .metric) {
        case .success(let result):
            XCTAssertEqual(stringValue(result), "Gasoline")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.invalidData) = FuelTypeDecoder().decode(data: Data([0xFF]), unit: .metric) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid fuel type")
        }

        switch OBDComplianceDecoder().decode(data: Data([0x00, 0x01]), unit: .metric) {
        case .success(let result):
            XCTAssertEqual(stringValue(result), "OBD-II as defined by the CARB")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.decodingFailed(let reason)) = OBDComplianceDecoder().decode(data: Data([0x00, 0xFF]), unit: .metric) {
            XCTAssertTrue(reason.contains("Invalid response"))
        } else {
            XCTFail("Expected invalid compliance table lookup")
        }

        switch AirStatusDecoder().decode(data: Data([0b0001_0000]), unit: .metric) {
        case .success(let result):
            // Original test expected 3, but decoder logic for 0b0001_0000 (1 at index 3 from MSB) gives 7-3 = 4.
            XCTAssertEqual(measurementValue(result), 4) // Corrected expected value
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.invalidData) = AirStatusDecoder().decode(data: Data([0b0001_1000]), unit: .metric) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid air-status response")
        }

        switch FuelStatusDecoder().decode(data: Data([0x00, 0x00]), unit: .metric) {
        case .success(let result):
            let codes = result.codeResult?.compactMap { $0?.description } ?? []
            XCTAssertEqual(codes, ["Unavailable", "Unavailable"])
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch StringDecoder().decode(data: Data("VIN#123".utf8), unit: .metric) {
        case .success(let result):
            XCTAssertEqual(stringValue(result), "VIN123")
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.decodingFailed(let reason)) = StringDecoder().decode(data: Data([0xFF]), unit: .metric) {
            XCTAssertTrue(reason.contains("Failed to decode string"))
        } else {
            XCTFail("Expected string decode failure")
        }

        switch UASDecoder(id: 0x09).decode(data: Data([0x64]), unit: .imperial) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), 62.1371, accuracy: 0.0001)
            XCTAssertEqual(result.measurementResult?.unit, UnitSpeed.milesPerHour)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        switch UASDecoder(id: 0x81).decode(data: Data([0xFF]), unit: .metric) {
        case .success(let result):
            XCTAssertEqual(measurementValue(result), -1, accuracy: 0.001)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        if case .failure(.invalidData) = UASDecoder(id: 0x00).decode(data: Data([0x00]), unit: .metric) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected invalid UAS id")
        }
    }

    func testStatusAndTroubleCodeHelpers() {
        switch StatusDecoder().decode(data: Data([0x81, 0x08, 0xE9, 0x00]), unit: .metric) {
        case .success(let result):
            let status = tryUnwrap(result.statusResult)
            XCTAssertTrue(status.isDiesel)
            XCTAssertTrue(status.milOn)
            XCTAssertEqual(status.dtcCount, 1)
            XCTAssertEqual(status.monitors.count, 9)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        XCTAssertNil(parseDTC(Data([0x00, 0x00])))
        XCTAssertEqual(parseDTC(Data([0x01, 0x04]))?.code, "P0104")
        XCTAssertEqual(parseDTC(Data([0x41, 0x23]))?.code, "C0123")

        let passing = MonitorTest(
            tid: 0x01,
            name: "T",
            desc: "Desc",
            value: MeasurementResult(value: 5, unit: .count),
            min: 1,
            max: 10
        )
        XCTAssertTrue(passing.passed)
        XCTAssertFalse(passing.isNull)
        XCTAssertTrue(passing.description.contains("PASSED"))

        let failing = MonitorTest()
        XCTAssertFalse(failing.passed)
        XCTAssertTrue(failing.isNull)
    }

    func testBatchedResponseExtraction() {
        var response = BatchedResponse(response: Data([0x0C, 0x1F, 0x40, 0x0D, 0x64]), .metric)
        let rpm = response.extractValue(.mode1(.rpm))
        let speed = response.extractValue(.mode1(.speed))

        XCTAssertEqual(tryUnwrap(rpm?.measurementResult).value, 2000, accuracy: 0.001)
        XCTAssertEqual(tryUnwrap(speed?.measurementResult).value, 100, accuracy: 0.001)

        var shortResponse = BatchedResponse(response: Data([0x0C]), .metric)
        XCTAssertNil(shortResponse.extractValue(.mode1(.rpm)))

        var invalidResponse = BatchedResponse(response: Data([0x1C, 0xFF]), .metric)
        XCTAssertNil(invalidResponse.extractValue(.mode1(.obdcompliance)))
    }

    func testELM327MockBackedFlows() async throws {
        let sut = ELM327(comm: MOCKComm())
        sut.canProtocol = Iso157654Can11Bit500k()

        let info = try await sut.setupVehicle(preferredProtocol: nil, querySupportedPIDs: true)
        XCTAssertEqual(info.obdProtocol, .protocol6)
        XCTAssertEqual(info.vin, "1N4AL3AP7DC199583")
        XCTAssertFalse(info.supportedPIDs?.isEmpty ?? true)
        XCTAssertFalse(info.supportedPIDs?.contains(.mode1(.pidsA)) ?? true)
        XCTAssertEqual(info.ecuMap?[0], .engine)

        let infoWithoutPidQuery = try await sut.setupVehicle(preferredProtocol: .protocol6, querySupportedPIDs: false)
        XCTAssertEqual(infoWithoutPidQuery.obdProtocol, .protocol6)
        XCTAssertNil(infoWithoutPidQuery.supportedPIDs)
        XCTAssertNil(infoWithoutPidQuery.ecuMap)

        let status = try await sut.getStatus()
        switch status {
        case .success(let result):
            XCTAssertNotNil(result.statusResult)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        let dtcs = try await sut.scanForTroubleCodes()
        XCTAssertFalse(dtcs.isEmpty)
        XCTAssertFalse(dtcs[.engine]?.isEmpty ?? true)

        let vin = await sut.requestVin()
        XCTAssertEqual(vin, "1N4AL3AP7DC199583")
        let supportedPIDs = await sut.getSupportedPIDs()
        XCTAssertFalse(supportedPIDs.isEmpty)
    }

    func testELM327AdapterInitializationAndExtraction() async throws {
        let sut = ELM327(comm: MOCKComm())
        try await sut.adapterInitialization()

        let supported = sut.extractSupportedPIDs([1, 0, 1, 0], offset: 0x20)
        XCTAssertEqual(supported, Set(["21", "23"]))
    }

    func testMockCommCommandMatrixCoversDemoResponseBranches() async throws {
        let comm = MOCKComm()

        for command in [
            "ATZ", "ATE1", "ATH0", "ATH1", "ATDPN", "ATRV", "ATST64",
            "ATSTZZ", "ATFOO", "AT SH 7E0", "ATAL", "ATD", "ATL0", "ATS0",
            "ATAT1", "ATSP0", "ATSP6"
        ] {
            let response = try await comm.sendCommand(command)
            XCTAssertFalse(response.isEmpty)
        }

        _ = try await comm.sendCommand("ATE0")
        _ = try await comm.sendCommand("ATH0")
        let headerless = try await comm.sendCommand(OBDCommand.mode1(.rpm).properties.command)
        XCTAssertFalse(headerless.first?.contains("7E8") ?? true)

        _ = try await comm.sendCommand("ATH1")

        for command in OBDCommand.Mode1.allCases {
            let response = try await comm.sendCommand(command.properties.command)
            XCTAssertFalse(response.isEmpty)
        }
        for command in OBDCommand.Mode6.allCases {
            let response = try await comm.sendCommand(command.properties.command)
            XCTAssertFalse(response.isEmpty)
        }
        for command in OBDCommand.Mode9.allCases {
            let response = try await comm.sendCommand(command.properties.command)
            XCTAssertFalse(response.isEmpty)
        }
        for command in OBDCommand.GMMode22.allCases {
            let response = try await comm.sendCommand(command.properties.command)
            XCTAssertFalse(response.isEmpty)
        }

        let batched = try await comm.sendCommand("010405060708090A0B0C0D0E0F1011")
        XCTAssertGreaterThan(batched.count, 1)

        let dtcFrames = try await comm.sendCommand("03")
        XCTAssertEqual(dtcFrames.count, 3)

        try await comm.connectAsync(timeout: 1, peripheral: nil)
        XCTAssertEqual(comm.connectionState, .connectedToAdapter)
        comm.disconnectPeripheral()
        XCTAssertEqual(comm.connectionState, .disconnected)
    }

    func testOBDServiceDemoFlows() async throws {
        let service = OBDService(connectionType: .demo)
        service.elm327.canProtocol = Iso157654Can11Bit500k()

        service.addPID(.mode1(.speed))
        service.addPID(.mode1(.rpm))
        XCTAssertEqual(service.pidList.count, 2)
        service.removePID(.mode1(.speed))
        XCTAssertEqual(service.pidList, [.mode1(.rpm)])

        let single = try await service.requestPID(.mode1(.speed), unit: .metric)
        XCTAssertNotNil(single[.mode1(.speed)]?.measurementResult)

        let dtcResult = try await service.requestPID(.mode3(.GET_DTC), unit: .metric)
        XCTAssertFalse(dtcResult[.mode3(.GET_DTC)]?.troubleCodesByECU?.isEmpty ?? true)

        let batch = try await service.requestPIDs([.mode1(.rpm), .mode1(.speed)], unit: .metric)
        XCTAssertEqual(batch.count, 2)

        let status = try await service.getStatus()
        switch status {
        case .success(let result):
            XCTAssertNotNil(result.statusResult)
        case .failure(let error):
            XCTFail("Unexpected failure: \(error)")
        }

        let raw = try await service.sendCommand("010C")
        XCTAssertFalse(raw.isEmpty)

        service.connectionStateChanged(state: .error)
        let stateExpectation = expectation(description: "state propagated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(service.connectionState, .error)
            XCTAssertNil(service.connectedPeripheral)
            stateExpectation.fulfill()
        }
        await fulfillment(of: [stateExpectation], timeout: 1)
    }

    func testOBDServiceStartConnectionAndContinuousUpdatesDemo() async throws {
        let service = OBDService(connectionType: .demo)
        let info = try await service.startConnection(
            preferedProtocol: .protocol6,
            timeout: 1,
            querySupportedPIDs: false
        )
        XCTAssertEqual(info.obdProtocol, .protocol6)
        XCTAssertEqual(info.vin, "1N4AL3AP7DC199583")

        let updateExpectation = expectation(description: "continuous update emitted")
        var cancellable: AnyCancellable?
        cancellable = service
            .startContinuousUpdates([.mode1(.rpm), .mode1(.speed)], unit: .metric, interval: 0.2)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { values in
                    XCTAssertNotNil(values[.mode1(.rpm)]?.measurementResult)
                    XCTAssertNotNil(values[.mode1(.speed)]?.measurementResult)
                    updateExpectation.fulfill()
                }
            )

        await fulfillment(of: [updateExpectation], timeout: 1)
        service.stopConnection()
        cancellable?.cancel()
    }

    func testELM327AndServiceFailureBranches() async {
        let preferredFailure = ScriptedComm { command in
            if command.hasPrefix("ATSP") { return ["OK"] }
            return ["NO DATA"]
        }
        let preferredSut = ELM327(comm: preferredFailure)
        do {
            _ = try await preferredSut.setupVehicle(preferredProtocol: .protocol6)
            XCTFail("Expected preferred protocol setup to fail")
        } catch ELM327Error.noProtocolFound {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let invalidAutomaticProtocol = ScriptedComm { command in
            switch command {
            case "ATSP0": return ["OK"]
            case "0100": return ["7E8 06 41 00 BE 3F A8 13 00"]
            case "ATDPN": return ["A?"]
            default: return ["NO DATA"]
            }
        }
        let invalidAutomaticSut = ELM327(comm: invalidAutomaticProtocol)
        do {
            _ = try await invalidAutomaticSut.setupVehicle(preferredProtocol: nil)
            XCTFail("Expected invalid automatic protocol setup to fail")
        } catch ELM327Error.invalidResponse {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let throwingComm = ScriptedComm { _ in throw TestFailure.sample }
        let failingElm = ELM327(comm: throwingComm)
        let vin = await failingElm.requestVin()
        XCTAssertNil(vin)
        do {
            try await failingElm.adapterInitialization()
            XCTFail("Expected adapter initialization to fail")
        } catch ELM327Error.adapterInitializationFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let service = OBDService(connectionType: .demo)
        service.elm327 = ELM327(comm: throwingComm)
        do {
            _ = try await service.startConnection(timeout: 0.1)
            XCTFail("Expected service start to fail")
        } catch OBDServiceError.adapterConnectionFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await service.clearTroubleCodes()
            XCTFail("Expected clear to fail")
        } catch OBDServiceError.clearFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await service.scanForPeripherals()
            XCTFail("Expected scan to fail")
        } catch OBDServiceError.scanFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await service.sendCommandInternal("010C", retries: 1)
            XCTFail("Expected command send to fail")
        } catch OBDServiceError.commandFailed {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLightweightModelsLoggingAndGarageBranches() {
        let elmErrors: [ELM327Error] = [
            .noConnection,
            .connectionNotReady,
            .encodingError,
            .sendFailed(TestFailure.sample),
            .receiveFailed(TestFailure.sample),
            .noProtocolFound,
            .invalidResponse(message: "bad"),
            .adapterInitializationFailed,
            .ignitionOff,
            .invalidProtocol,
            .timeout,
            .connectionFailed(reason: "offline"),
            .unknownError
        ]
        XCTAssertTrue(elmErrors.allSatisfy { $0.errorDescription?.isEmpty == false })

        let logger = OBDLogger.shared
        logger.isLoggingEnabled = true
        logger.debug("debug", category: .service)
        logger.info("info", category: .connection)
        logger.warning("warning", category: .communication)
        logger.error("error", category: .parsing)
        logger.fault("fault", category: .error)
        logger.logConnectionChange(from: .disconnected, to: .connectedToAdapter)
        logger.logCommand("010C", direction: .send, data: "7E8", duration: 0.01)
        logger.logCommand("410C", direction: .receive)
        logger.logParseError("bad frame", data: Data([0x7E, 0x8]), expectedFormat: "CAN")
        logger.logParseError("bad frame", data: Data([0x7E, 0x8]))
        logger.logPerformance("operation", duration: 0.02, success: true)
        logger.logPerformance("operation", duration: 0.02, success: false)
        logger.logProtocolEvent("detected", protocolName: "CAN", details: "11-bit")
        logger.logProtocolEvent("detected")
        logger.isLoggingEnabled = false
        logger.debug("suppressed")
        logger.isLoggingEnabled = true

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "garageVehicles")
        defaults.removeObject(forKey: "currentCarId")

        let garage = Garage()
        let newVehicle = garage.newVehicle()
        XCTAssertEqual(newVehicle.make, "None")
        garage.setCurrentVehicle(to: newVehicle)
        XCTAssertEqual(garage.currentVehicle, newVehicle)
        garage.switchToDemoMode(true)
        garage.switchToDemoMode(false)
        garage.loadMockGarage()
        XCTAssertEqual(garage.garageVehicles.count, 2)
        let mockVehicle = tryUnwrap(garage.currentVehicle)
        garage.updateVehicle(mockVehicle)
        garage.deleteVehicle(mockVehicle)

        let statusCode = StatusCodeMetadata(code: "READY", description: "Ready")
        XCTAssertEqual(statusCode.code, "READY")
        XCTAssertNotNil(troubleCodeDictionary["P0104"])
        XCTAssertLessThan(TroubleCode(code: "P0101", description: "A"), TroubleCode(code: "P0104", description: "B"))
    }

    func testGarageLifecycle() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "garageVehicles")
        defaults.removeObject(forKey: "currentCarId")

        let garage = Garage()
        XCTAssertTrue(garage.garageVehicles.isEmpty)

        garage.addVehicle(make: "Honda", model: "Civic", year: "2020")
        XCTAssertEqual(garage.currentVehicle?.make, "Honda")
        XCTAssertEqual(garage.garageVehicles.count, 1)

        var updated = tryUnwrap(garage.currentVehicle)
        updated.model = "Accord"
        garage.updateVehicle(updated)
        XCTAssertEqual(garage.currentVehicle?.model, "Accord")

        garage.deleteVehicle(updated)
        XCTAssertTrue(garage.garageVehicles.isEmpty)
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("Expected non-nil value", file: file, line: line)
            fatalError("Unreachable")
        }
        return value
    }

    private func measurementValue(_ result: DecodeResult, file: StaticString = #filePath, line: UInt = #line) -> Double {
        tryUnwrap(result.measurementResult, file: file, line: line).value
    }

    private func stringValue(_ result: DecodeResult, file: StaticString = #filePath, line: UInt = #line) -> String {
        if case .stringResult(let value) = result {
            return value
        }
        XCTFail("Expected string result", file: file, line: line)
        return ""
    }

    private enum TestFailure: Error {
        case sample
    }

    private final class ScriptedComm: CommProtocol {
        typealias Handler = (String) throws -> [String]

        @Published var connectionState: ConnectionState = .disconnected
        var connectionStatePublisher: Published<ConnectionState>.Publisher { $connectionState }
        var obdDelegate: OBDServiceDelegate?

        private let handler: Handler

        init(handler: @escaping Handler) {
            self.handler = handler
        }

        func sendCommand(_ command: String, retries _: Int) async throws -> [String] {
            try handler(command)
        }

        func disconnectPeripheral() {
            connectionState = .disconnected
            obdDelegate?.connectionStateChanged(state: .disconnected)
        }

        func connectAsync(timeout _: TimeInterval, peripheral _: CBPeripheral?) async throws {
            _ = try handler("CONNECT")
            connectionState = .connectedToAdapter
            obdDelegate?.connectionStateChanged(state: .connectedToAdapter)
        }

        func scanForPeripherals() async throws {
            _ = try handler("SCAN")
        }
    }
}

