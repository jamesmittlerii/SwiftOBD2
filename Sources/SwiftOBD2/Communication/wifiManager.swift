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
        tcpOptions.connectionTimeout = Int(totalTimeout / 2)
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        tcp = NWConnection(host: host, port: port, using: parameters)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var timeoutWorkItem: DispatchWorkItem?
            var didResume = false

            func resumeOnce(_ resume: () -> Void) {
                // Ensure only the first path resumes the continuation
                guard !didResume else { return }
                didResume = true
                // Prevent further callbacks from firing
                timeoutWorkItem?.cancel()
                timeoutWorkItem = nil
                // Detach handler to avoid more state callbacks trying to resume
                tcp?.stateUpdateHandler = nil
                resume()
            }

            // Manual timeout
            timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.connectionState != .connectedToAdapter {
                    obdError("Total connection timeout exceeded. Cancelling connection.", category: .wifi)
                    self.connectionState = .disconnected
                    // Cancel triggers NWConnection to emit .cancelled/.failed; our resumeOnce prevents double resume
                    self.tcp?.cancel()
                    resumeOnce {
                        continuation.resume(throwing: CommunicationError.connectionTimedOut)
                    }
                }
            }
            if let timeoutWorkItem {
                DispatchQueue.main.asyncAfter(deadline: .now() + totalTimeout, execute: timeoutWorkItem)
            }
            
            tcp?.stateUpdateHandler = { [weak self] newState in
                guard let self = self else { return }
                switch newState {
                case .ready:
                    obdInfo("Connected to \(self.host.debugDescription):\(self.port.debugDescription)", category: .wifi)
                    self.connectionState = .connectedToAdapter
                    resumeOnce {
                        continuation.resume(returning: ())
                    }
                    
                case let .failed(error):
                    obdError("Connection failed: \(error.localizedDescription)",category: .wifi)
                    self.connectionState = .disconnected
                    resumeOnce {
                        continuation.resume(throwing: CommunicationError.errorOccurred(error))
                    }

                case let .waiting(error):
                    obdWarning("Connection waiting: \(error.localizedDescription)", category: .wifi)

                case .cancelled:
                    // Treat cancelled as a failure unless already resumed
                    obdWarning("Connection cancelled", category: .wifi)
                    self.connectionState = .disconnected
                    resumeOnce {
                        continuation.resume(throwing: CommunicationError.errorOccurred(NWError.posix(.ECANCELED)))
                    }

                default:
                    break
                }
            }
            tcp?.start(queue: .main)
        }
    }

    func sendCommandOld(_ command: String, retries: Int) async throws -> [String] {
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
                    try await Task.sleep(nanoseconds: 100_000_000)
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

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
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
                        
                        let text = String(data: buffer, encoding: .utf8) ?? ""
                        
                        if text.contains(">") {
                            obdDebug("received: \(text)", category: .wifi)
                            continuation.resume(returning: text)
                            return
                        }
                        
                        if !isComplete {
                            receiveLoop()
                        } else {
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
    
    func sendCommand(_ command: String, retries: Int) async throws -> [String] {
        guard let tcp else { throw ELM327Error.noConnection }

        guard tcp.state == .ready else {
            throw ELM327Error.connectionNotReady
        }

        obdDebug("Sending: \(command)", category: .wifi)
        
        let commandWithCR = command + "\r"

        guard let data = commandWithCR.data(using: .utf8) else {
            throw ELM327Error.encodingError
        }

        var attempts = 0
        var lastError: Error?

        while attempts <= retries {
            attempts += 1
            do {
                try await send(data, over: tcp)
                let responseString = try await receiveUntilPrompt(over: tcp)
                let cleaned = cleanELMResponse(responseString)
                
                obdDebug("received: \(cleaned)", category: .wifi)
                return cleaned
            } catch {
                lastError = error
                if attempts > retries { break }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        throw lastError ?? ELM327Error.invalidResponse(message: "No response after \(retries) retries")
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: ELM327Error.sendFailed(error as Error))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveUntilPrompt(over connection: NWConnection) async throws -> String {
        var fullBuffer = Data()
        let timeoutNanos: UInt64 = 2_500_000_000 // 2.5 seconds

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw ELM327Error.timeout
            }

            group.addTask { [weak self] in
                guard let self = self else { throw ELM327Error.noConnection }
                while true {
                    let chunk = try await self.receiveChunk(over: connection)
                    fullBuffer.append(chunk)

                    if let str = String(data: fullBuffer, encoding: .utf8),
                       str.contains(">") {
                        return str
                    }
                }
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func receiveChunk(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: ELM327Error.receiveFailed(error as Error))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ELM327Error.invalidResponse(message: "Empty receive"))
                }
            }
        }
    }

    private func cleanELMResponse(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: ">", with: "")
            .split(separator: "\r")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
