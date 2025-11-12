import Combine
import CoreBluetooth
import Foundation

public enum ConnectionType: String, CaseIterable {
    case bluetooth = "Bluetooth"
    case wifi = "Wi-Fi"
    case demo = "Demo"
}

public protocol OBDServiceDelegate: AnyObject {
    func connectionStateChanged(state: ConnectionState)
}

struct Command: Codable {
    var bytes: Int
    var command: String
    var decoder: String
    var description: String
    var live: Bool
    var maxValue: Int
    var minValue: Int
}

public class ConfigurationService {
    public static var shared = ConfigurationService()
    public var connectionType: ConnectionType {
        get {
            let rawValue = UserDefaults.standard.string(forKey: "connectionType") ?? "Bluetooth"
            return ConnectionType(rawValue: rawValue) ?? .bluetooth
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "connectionType")
        }
    }
}

/// A class that provides an interface to the ELM327 OBD2 adapter and the vehicle.
///
/// - Key Responsibilities:
///   - Establishing a connection to the adapter and the vehicle.
///   - Sending and receiving OBD2 commands.
///   - Providing information about the vehicle.
///   - Managing the connection state.
public class OBDService: ObservableObject, OBDServiceDelegate {
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var connectedPeripheral: CBPeripheral?
    @Published public var connectionType: ConnectionType {
        didSet {
            switchConnectionType(connectionType)
            ConfigurationService.shared.connectionType = connectionType
        }
    }

    /// Optional Wi-Fi configuration
    private var wifiHost: String?
    private var wifiPort: UInt16?

    /// The internal ELM327 object responsible for direct adapter interaction.
    var elm327: ELM327

    private var cancellables = Set<AnyCancellable>()

    // Keep a weak reference to BLEManager (only valid when using Bluetooth)
    private weak var bleManagerRef: BLEManager?

    /// Initializes the OBDService object.
    ///
    /// - Parameters:
    ///   - connectionType: The desired connection type (default is Bluetooth).
    ///   - host: Optional Wi‑Fi host to use when `connectionType == .wifi`. Defaults to "192.168.4.207" if not provided.
    ///   - port: Optional Wi‑Fi port to use when `connectionType == .wifi`. Defaults to 35000 if not provided.
    public init(connectionType: ConnectionType = .bluetooth, host: String? = nil, port: UInt16? = nil) {
        self.connectionType = connectionType
        self.wifiHost = host
        self.wifiPort = port
#if targetEnvironment(simulator) && false
        elm327 = ELM327(comm: MOCKComm())
#else
        switch connectionType {
        case .bluetooth:
            let bleManager = BLEManager()
            bleManagerRef = bleManager
            elm327 = ELM327(comm: bleManager)
        case .wifi:
            let resolvedHost = host ?? "192.168.0.10"
            let resolvedPort = port ?? 35000
            elm327 = ELM327(comm: WifiManager(host: resolvedHost, port: resolvedPort))
        case .demo:
            elm327 = ELM327(comm: MOCKComm())
        }
#endif
        elm327.obdDelegate = self
        bindPeripheralIfNeeded()
    }

    // MARK: - Connection Handling

    public func connectionStateChanged(state: ConnectionState) {
        DispatchQueue.main.async {
            let oldState = self.connectionState
            self.connectionState = state
            if oldState != state {
                OBDLogger.shared.logConnectionChange(from: oldState, to: state)
            }

            // Clear connectedPeripheral on terminal/disconnected states
            switch state {
            case .disconnected, .error:
                self.connectedPeripheral = nil
            default:
                break
            }
        }
    }

    /// Initiates the connection process to the OBD2 adapter and vehicle.
    ///
    /// - Parameter preferedProtocol: The optional OBD2 protocol to use (if supported).
    /// - Returns: Information about the connected vehicle (`OBDInfo`).
    /// - Throws: Errors that might occur during the connection process.
    public func startConnection(preferedProtocol: PROTOCOL? = nil, timeout: TimeInterval = 30, querySupportedPIDs: Bool = true,  peripheral: CBPeripheral? = nil) async throws -> OBDInfo {
        let startTime = CFAbsoluteTimeGetCurrent()
        obdInfo("Starting connection with timeout: \(timeout)s", category: .connection)
        
        do {
            
            /* DELETE THIS
             
             BMW was sending multiple messages for 0100
            let myProtocol = ISO_15765_4_11bit_500k()
            let r100: [String] = ["7EB06410098188001","7E8064100BE3EA813","7ED06410098188001","7EF06410098188001"]
            let messages = try myProtocol.parse(r100)
             */
            
            
            obdDebug("Connecting to adapter...", category: .connection)
            try await elm327.connectToAdapter(timeout: timeout, peripheral: peripheral)
            
            obdDebug("Initializing adapter...", category: .connection)
            try await elm327.adapterInitialization()
            
            obdDebug("Initializing vehicle connection...", category: .connection)
            let vehicleInfo = try await initializeVehicle(preferedProtocol, querySupportedPIDs: querySupportedPIDs)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            OBDLogger.shared.logPerformance("Connection established", duration: duration, success: true)
            obdInfo("Successfully connected to vehicle: \(vehicleInfo.vin ?? "Unknown")", category: .connection)

            return vehicleInfo
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            OBDLogger.shared.logPerformance("Connection failed", duration: duration, success: false)
            obdError("Connection failed: \(error.localizedDescription)", category: .connection)
            throw OBDServiceError.adapterConnectionFailed(underlyingError: error) // Propagate
        }
    }

    /// Initializes communication with the vehicle and retrieves vehicle information.
    ///
    /// - Parameter preferedProtocol: The optional OBD2 protocol to use (if supported).
    /// - Returns: Information about the connected vehicle (`OBDInfo`).
    /// - Throws: Errors if the vehicle initialization process fails.
    func initializeVehicle(_ preferedProtocol: PROTOCOL?, querySupportedPIDs: Bool = true) async throws -> OBDInfo {
        let obd2info = try await elm327.setupVehicle(preferredProtocol: preferedProtocol, querySupportedPIDs: querySupportedPIDs)
        return obd2info
    }

    /// Terminates the connection with the OBD2 adapter.
    public func stopConnection() {
        elm327.stopConnection()
    }

    /// Switches the active connection type (between Bluetooth and Wi-Fi).
    ///
    /// - Parameter connectionType: The new desired connection type.
    private func switchConnectionType(_ connectionType: ConnectionType) {
        stopConnection()
        initializeELM327()
        bindPeripheralIfNeeded()
    }

    private func initializeELM327() {
        switch connectionType {
        case .bluetooth:
            let bleManager = BLEManager()
            bleManagerRef = bleManager
            elm327 = ELM327(comm: bleManager)
        case .wifi:
            let resolvedHost = wifiHost ?? "192.168.4.207"
            let resolvedPort = wifiPort ?? 35000
            elm327 = ELM327(comm: WifiManager(host: resolvedHost, port: resolvedPort))
            bleManagerRef = nil
            connectedPeripheral = nil
        case .demo:
            elm327 = ELM327(comm: MOCKComm())
            bleManagerRef = nil
            connectedPeripheral = nil
        }
        elm327.obdDelegate = self
    }

    // Subscribe to BLE peripheral updates when using Bluetooth
    private func bindPeripheralIfNeeded() {
        // FIX: Set<AnyCancellable> doesn’t support removeAll(where:)
        // Just clear the set (subscriptions will be released and canceled)
        cancellables.removeAll()

        guard let ble = bleManagerRef else { return }

        // Expose a publisher from BLEManager to observe connected peripheral
        // and mirror to OBDService.connectedPeripheral
        ble.peripheralPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peripheral in
                self?.connectedPeripheral = peripheral
            }
            .store(in: &cancellables)
    }

    // MARK: - Request Handling

    var pidList: [OBDCommand] = []

    /// Sends an OBD2 command to the vehicle and returns a publisher with the result.
    /// - Parameter command: The OBD2 command to send.
    /// - Returns: A publisher with the measurement result.
    /// - Throws: Errors that might occur during the request process.
    public func startContinuousUpdates(
        _ pids: [OBDCommand],
        unit: MeasurementUnit = .metric,
        interval: TimeInterval = 1
    ) -> AnyPublisher<[OBDCommand: DecodeResult], Error> {

        // Adaptive backoff state
        let minInterval: TimeInterval = max(0.2, interval) // don’t go below 200ms
        let maxInterval: TimeInterval = max(interval * 4, 2.0) // up to 4x or at least 2s
        var currentInterval: TimeInterval = interval
        var consecutiveFailures = 0
        var inFlight = false

        // A subject that lets us reconfigure the timer dynamically
        let intervalSubject = CurrentValueSubject<TimeInterval, Never>(currentInterval)

        // Build a dynamic timer stream driven by intervalSubject
        let timerStream = intervalSubject
            .removeDuplicates()
            .flatMap { interval -> AnyPublisher<Date, Never> in
                Timer.publish(every: interval, on: .main, in: .common)
                    .autoconnect()
                    .eraseToAnyPublisher()
            }

        return timerStream
            .flatMap { [weak self] _ -> Future<[OBDCommand: DecodeResult], Error> in
                Future { promise in
                    guard let self = self else {
                        promise(.failure(OBDServiceError.notConnectedToVehicle))
                        return
                    }

                    // Skip tick if a previous cycle is still running
                    if inFlight {
                        return
                    }
                    inFlight = true

                    Task(priority: .userInitiated) {
                        var aggregatedResults: [OBDCommand: DecodeResult] = [:]
                        var hadFailureThisCycle = false

                        for pid in pids {
                            do {
                               let singleResult = try await self.requestPID(pid, unit: unit)
                               // let singleResult = try await self.requestPIDs([pid], unit: unit)
                                for (command, value) in singleResult {
                                    aggregatedResults[command] = value
                                }
                            } catch {
                                hadFailureThisCycle = true
                                obdWarning("requestPID failed for \(pid): \(error)", category: .communication)
                                // continue to next PID for resilience
                                continue
                            }
                        }

                        // Adjust backoff after the cycle
                        if hadFailureThisCycle {
                            consecutiveFailures += 1
                            // Exponential backoff with cap
                            currentInterval = min(maxInterval, currentInterval * 1.5)
                            intervalSubject.send(currentInterval)
                            obdInfo("Backoff increased: interval=\(currentInterval)s (failures=\(consecutiveFailures))", category: .communication)
                        } else {
                            // On success, slowly recover toward minInterval
                            consecutiveFailures = 0
                            currentInterval = max(minInterval, currentInterval * 0.9)
                            intervalSubject.send(currentInterval)
                        }

                        inFlight = false
                        promise(.success(aggregatedResults))
                    }
                }
            }
            .eraseToAnyPublisher()
    }

    /// Adds an OBD2 command to the list of commands to be requested.
    public func addPID(_ pid: OBDCommand) {
        pidList.append(pid)
    }

    /// Removes an OBD2 command from the list of commands to be requested.
    public func removePID(_ pid: OBDCommand) {
        pidList.removeAll { $0 == pid }
    }

    /// Sends an OBD2 command to the vehicle and returns the raw response.
    /// - Parameter command: The OBD2 command to send.
    /// - Returns: measurement result
    /// - Throws: Errors that might occur during the request process.
    public func requestPIDs(_ commands: [OBDCommand], unit: MeasurementUnit) async throws -> [OBDCommand: DecodeResult] {
        let response = try await sendCommandInternal("01" + commands.compactMap { $0.properties.command.dropFirst(2) }.joined(), retries: 1)

        guard let responseData = try elm327.canProtocol?.parse(response).first?.data else { return [:] }

        var batchedResponse = BatchedResponse(response: responseData, unit)

        let results: [OBDCommand: DecodeResult] = commands.reduce(into: [:]) { result, command in
            let measurement = batchedResponse.extractValue(command)
            result[command] = measurement
        }

        return results
    }
    
    public func sendCommand(_ command: String) async throws -> [String] {
        return try await elm327.sendCommand(command)
    }
    
    /// Sends an OBD2 command to the vehicle and returns the raw response.
    /// - Parameter command: The OBD2 command to send.
    /// - Returns: measurement result
    /// - Throws: Errors that might occur during the request process.
    public func requestPID(_ command: OBDCommand, unit: MeasurementUnit) async throws -> [OBDCommand: DecodeResult] {
        
        
        let response = try await sendCommandInternal(command.properties.command, retries: 1)
        // JEM let response = try await sendCommandInternal("01" + command.properties.command.dropFirst(2), retries: 1)

        guard let responseData = try elm327.canProtocol?.parse(response).first?.data else { return [:] }

        
        let hex = responseData.map { String(format: "%02X", $0) }.joined()
        obdDebug("parsed response: \(hex)")
        
        
        // Validate that the first payload byte (what BatchedResponse sees first)
        // matches the requested PID byte from the command (e.g., 0x0F for 010F).
        // responseData[0] is the service (0x41 for Mode 01), payload starts after that.
        guard responseData.count >= 2 else {
            throw OBDServiceError.commandFailed(command: command.properties.command, error: DecodeError.noData)
        }

        let pidHex = String(command.properties.command.suffix(2))
        let requestedPid = UInt8(pidHex, radix: 16) ?? 0x00
        let firstPayloadByte = responseData.first ?? 0x00

        /* JEM
        if firstPayloadByte != requestedPid {
            obdWarning(
                "PID echo mismatch. Expected PID 0x\(String(format: "%02X", requestedPid)), got 0x\(String(format: "%02X", firstPayloadByte))",
                category: .parsing
            )
            throw OBDServiceError.pidMismatch(expected: requestedPid, actual: firstPayloadByte)
        } */

        var batchedResponse = BatchedResponse(response: responseData, unit)

        if let value = batchedResponse.extractValue(command) {
            return [command: value]
        } else {
            return [:]
        }
    }
    
    
    /// Sends an OBD2 command to the vehicle and returns the raw response.
    ///  - Parameter command: The OBD2 command to send.
    ///  - Returns: The raw response from the vehicle.
    ///  - Throws: Errors that might occur during the request process.
    public func sendCommand(_ command: OBDCommand) async throws -> Result<DecodeResult, DecodeError> {
        do {
            let response = try await sendCommandInternal(command.properties.command, retries: 3)
            guard let responseData = try elm327.canProtocol?.parse(response).first?.data else {
                return .failure(.noData)
            }
            
            let pidsize = command.properties.command.count/2 - 1
            return command.properties.decode(data: responseData.dropFirst())
        } catch {
            throw OBDServiceError.commandFailed(command: command.properties.command, error: error)
        }
    }

    /// Sends an OBD2 command to the vehicle and returns the raw response.
    ///   - Parameter command: The OBD2 command to send.
    ///   - Returns: The raw response from the vehicle.
    public func getSupportedPIDs() async -> [OBDCommand] {
        await elm327.getSupportedPIDs()
    }

    ///  Scans for trouble codes and returns the result.
    ///  - Returns: The trouble codes found on the vehicle.
    ///  - Throws: Errors that might occur during the request process.
    public func scanForTroubleCodes() async throws -> [ECUID: [TroubleCodeMetadata]] {
        do {
            return try await elm327.scanForTroubleCodes()
        } catch {
            throw OBDServiceError.scanFailed(underlyingError: error)
        }
    }

    /// Clears the trouble codes found on the vehicle.
    ///  - Throws: Errors that might occur during the request process.
    ///     - `OBDServiceError.notConnectedToVehicle` if the adapter is not connected to a vehicle.
    public func clearTroubleCodes() async throws {
        do {
            try await elm327.clearTroubleCodes()
        } catch {
            throw OBDServiceError.clearFailed(underlyingError: error)
        }
    }

    /// Returns the vehicle's status.
    ///  - Returns: The vehicle's status.
    ///  - Throws: Errors that might occur during the request process.
    public func getStatus() async throws -> Result<DecodeResult, DecodeError> {
        do {
            return try await elm327.getStatus()
        } catch {
            throw error
        }
    }

    /// Sends a raw command to the vehicle and returns the raw response.
    /// - Parameter message: The raw command to send.
    /// - Returns: The raw response from the vehicle.
    /// - Throws: Errors that might occur during the request process.
    public func sendCommandInternal(_ message: String, retries: Int) async throws -> [String] {
        do {
            return try await elm327.sendCommand(message, retries: retries)
        } catch {
            throw OBDServiceError.commandFailed(command: message, error: error)
        }
    }

    public func connectToPeripheral(peripheral: CBPeripheral) async throws {
        do {
            try await elm327.connectToAdapter(timeout: 5, peripheral: peripheral)
        } catch {
            throw OBDServiceError.adapterConnectionFailed(underlyingError: error)
        }
    }

    public func scanForPeripherals() async throws {
        do {
            self.isScanning = true
            try await elm327.scanForPeripherals()
            self.isScanning = false
        } catch {
            throw OBDServiceError.scanFailed(underlyingError: error)
        }
    }
}

public enum OBDServiceError: Error {
    case noAdapterFound
    case notConnectedToVehicle
    case adapterConnectionFailed(underlyingError: Error)
    case scanFailed(underlyingError: Error)
    case clearFailed(underlyingError: Error)
    case commandFailed(command: String, error: Error)
    case pidMismatch(expected: UInt8, actual: UInt8)
}

public struct MeasurementResult: Equatable {
    public var value: Double
    public let unit: Unit
	
	public init(value: Double, unit: Unit) {
		self.value = value
		self.unit = unit
	}
}

extension MeasurementResult: Comparable {
    public static func < (lhs: MeasurementResult, rhs: MeasurementResult) -> Bool {
        guard lhs.unit == rhs.unit else { return false }
        return lhs.value < rhs.value
    }
}

public extension MeasurementResult {
	static func mock(_ value: Double = 125, _ suffix: String = "km/h") -> MeasurementResult {
		.init(value: value, unit: .init(symbol: suffix))
	}
}

public func getVINInfo(vin: String) async throws -> VINResults {
    let endpoint = "https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/\(vin)?format=json"

    guard let url = URL(string: endpoint) else {
        throw URLError(.badURL)
    }

    let (data, response) = try await URLSession.shared.data(from: url)

    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(VINResults.self, from: data)
    return decoded
}

public struct VINResults: Codable {
    public let Results: [VINInfo]
}

public struct VINInfo: Codable, Hashable {
    public let Make: String
    public let Model: String
    public let ModelYear: String
    public let EngineCylinders: String
}
