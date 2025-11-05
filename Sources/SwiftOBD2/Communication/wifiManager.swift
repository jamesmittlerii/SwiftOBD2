//
//  wifiManager.swift
//
//
//  Created by kemo konteh on 2/26/24.
//

import CoreBluetooth
import Foundation
import Network
import OSLog

protocol CommProtocol {
    func sendCommand(_ command: String, retries: Int) async throws -> [String]
    func disconnectPeripheral()
    func connectAsync(timeout: TimeInterval, peripheral: CBPeripheral?) async throws
    func scanForPeripherals() async throws
    var connectionStatePublisher: Published<ConnectionState>.Publisher { get }
    var obdDelegate: OBDServiceDelegate? { get set }
}

enum CommunicationError: Error {
    case invalidData
    case errorOccurred(Error)
    case connectionTimedOut
}

class WifiManager: CommProtocol {
    @Published var connectionState: ConnectionState = .disconnected

    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app", category: "wifiManager")

    var obdDelegate: OBDServiceDelegate?

    var connectionStatePublisher: Published<ConnectionState>.Publisher { $connectionState }

    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port

    var tcp: NWConnection?

    init(host: String, port: UInt16) {
        self.host = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            fatalError("Invalid port: \(port)")
        }
        self.port = nwPort
    }
    
    func connectAsync(timeout totalTimeout: TimeInterval,peripheral _: CBPeripheral? = nil) async throws {
        let tcpOptions = NWProtocolTCP.Options()
        // Set a reasonable individual handshake timeout (e.g., half the total timeout)
        tcpOptions.connectionTimeout = Int(totalTimeout / 2)
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
               
        tcp = NWConnection(host: host, port: port, using: parameters)

        // Use a task group or a manual timer to manage the total timeout
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var timeoutWorkItem: DispatchWorkItem?

            // Define a function to handle the timeout cancellation
            let cancelOnTimeout = { [weak self] in
                guard let self = self else { return }
                if self.connectionState != .connectedToAdapter {
                    self.logger.error("Total connection timeout exceeded. Cancelling connection.")
                    self.connectionState = .disconnected
                    self.tcp?.cancel()
                    // Resume with a timeout error if the continuation hasn't already resumed
                    continuation.resume(throwing: CommunicationError.connectionTimedOut)
                }
            }
            
            // Schedule the manual timeout
            timeoutWorkItem = DispatchWorkItem(block: cancelOnTimeout)
            DispatchQueue.main.asyncAfter(deadline: .now() + totalTimeout, execute: timeoutWorkItem!)
            
            tcp?.stateUpdateHandler = { [weak self] newState in
                guard let self = self else { return }
                switch newState {
                case .ready:
                    // If successful, cancel the pending timeout work item
                    timeoutWorkItem?.cancel()
                    self.logger.info("Connected to \(self.host.debugDescription):\(self.port.debugDescription)")
                    self.connectionState = .connectedToAdapter
                    continuation.resume(returning: ())
                    
                case let .failed(error):
                    // If failed, cancel the pending timeout work item
                    timeoutWorkItem?.cancel()
                    self.logger.error("Connection failed: \(error.localizedDescription)")
                    self.connectionState = .disconnected
                    continuation.resume(throwing: CommunicationError.errorOccurred(error))
                    
                case let .waiting(error):
                    // This is the state where you are seeing the ETIMEDOUT message
                    self.logger.warning("Connection waiting: \(error.localizedDescription)")
                    
                default:
                    break
                }
            }
            tcp?.start(queue: .main)
        }
    }

   

    func sendCommand(_ command: String, retries: Int) async throws -> [String] {
        guard let data = "\(command)\r".data(using: .ascii) else {
            throw CommunicationError.invalidData
        }
        //logger.info("Sending: \(command)")
        return try await sendCommandInternal(data: data, retries: retries)
    }

    private func sendCommandInternal(data: Data, retries: Int) async throws -> [String] {
        for attempt in 1 ... retries {
            do {
                let response = try await sendAndReceiveData(data)
                if let lines = processResponse(response) {
                    return lines
                } else if attempt < retries {
                    logger.info("No data received, retrying attempt \(attempt + 1) of \(retries)...")
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.5 seconds delay
                }
            } catch {
                if attempt == retries {
                    throw error
                }
                logger.warning("Attempt \(attempt) failed, retrying: \(error.localizedDescription)")
            }
        }
        throw CommunicationError.invalidData
    }

    private func sendAndReceiveData(_ data: Data) async throws -> String {
        guard let tcpConnection = tcp else {
             throw CommunicationError.invalidData
         }
        let logger = self.logger // Avoid capturing `self` directly

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            tcpConnection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    logger.error("Error sending data: \(error.localizedDescription)")
                    continuation.resume(throwing: CommunicationError.errorOccurred(error))
                    return
                }

                tcpConnection.receive(minimumIncompleteLength: 1, maximumLength: 500) { data, _, _, error in
                    if let error = error {
                        logger.error("Error receiving data: \(error.localizedDescription)")
                        continuation.resume(throwing: CommunicationError.errorOccurred(error))
                        return
                    }

                    guard let response = data, let responseString = String(data: response, encoding: .utf8) else {
                        logger.warning("Received invalid or empty data")
                        continuation.resume(throwing: CommunicationError.invalidData)
                        return
                    }

                    continuation.resume(returning: responseString)
                }
            })
        }
    }

    private func processResponse(_ response: String) -> [String]? {
        //logger.info("Processing response: \(response)")
        var lines = response.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            logger.warning("Empty response lines")
            return nil
        }

        if lines.last?.contains(">") == true {
            lines.removeLast()
        }

        if lines.first?.lowercased() == "no data" {
            return nil
        }

        return lines
    }

    func disconnectPeripheral() {
        tcp?.cancel()
    }

    func scanForPeripherals() async throws {}
}
