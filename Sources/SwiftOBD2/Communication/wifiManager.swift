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
                    obdError("Total connection timeout exceeded. Cancelling connection.", category: .wifi)
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
                    obdInfo("Connected to \(self.host.debugDescription):\(self.port.debugDescription)", category: .wifi)
                    self.connectionState = .connectedToAdapter
                    continuation.resume(returning: ())
                    
                case let .failed(error):
                    // If failed, cancel the pending timeout work item
                    timeoutWorkItem?.cancel()
                    obdError("Connection failed: \(error.localizedDescription)",category: .wifi)
                    self.connectionState = .disconnected
                    continuation.resume(throwing: CommunicationError.errorOccurred(error))
                    
                case let .waiting(error):
                    // This is the state where you are seeing the ETIMEDOUT message
                    obdWarning("Connection waiting: \(error.localizedDescription)", category: .wifi)
                    
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
        obdDebug("Sending: \(command)", category: .wifi)
        return try await sendCommandInternal(data: data, retries: retries)
    }

    private func sendCommandInternal(data: Data, retries: Int) async throws -> [String] {
        for attempt in 1 ... retries {
            do {
                let response = try await sendAndReceiveData(data)
                if let lines = processResponse(response) {
                    return lines
                } else if attempt < retries {
                    obdInfo("No data received, retrying attempt \(attempt + 1) of \(retries)...", category: .wifi)
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.5 seconds delay
                }
            } catch {
                if attempt == retries {
                    throw error
                }
                obdWarning("Attempt \(attempt) failed, retrying: \(error.localizedDescription)", category: .wifi)
            }
        }
        throw CommunicationError.invalidData
    }

    private func sendAndReceiveData(_ data: Data) async throws -> String {
        guard let tcpConnection = tcp else {
            throw CommunicationError.invalidData
        }

        return try await withCheckedThrowingContinuation { continuation in
            
            // Step 1: Send the command
            tcpConnection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: CommunicationError.errorOccurred(error))
                    return
                }

                var buffer = Data()
                
                func receiveLoop() {
                    tcpConnection.receive(minimumIncompleteLength: 1, maximumLength: 512) { chunk, _, isComplete, error in
                        
                        if let error = error {
                            continuation.resume(throwing: CommunicationError.errorOccurred(error))
                            return
                        }
                        
                        guard let chunk = chunk else {
                            continuation.resume(throwing: CommunicationError.invalidData)
                            return
                        }
                        
                        buffer.append(chunk)
                        
                        // Try to decode into UTF-8
                        let text = String(data: buffer, encoding: .utf8) ?? ""
                        
                        // ✅ ELM327 is done
                        if text.contains(">") {
                            //let cleaned = text.replacingOccurrences(of: ">", with: "")
                            obdDebug("received: \(text)", category: .wifi)
                            continuation.resume(returning: text)
                            return
                        }
                        
                        // ✅ Continue receiving until prompt arrives
                        if !isComplete {
                            receiveLoop()
                        } else {
                            // No prompt AND stream ended? -> Error
                            continuation.resume(throwing: CommunicationError.invalidData)
                        }
                    }
                }
                
                // Begin receive loop
                receiveLoop()
            })
        }
    }


    private func processResponse(_ response: String) -> [String]? {
        //logger.info("Processing response: \(response)")
        var lines = response.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            obdWarning("Empty response lines",category: .wifi)
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
