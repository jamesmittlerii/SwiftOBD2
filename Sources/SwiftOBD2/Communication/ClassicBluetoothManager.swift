//
//  ClassicBluetoothManager.swift
//
//  Bluetooth Classic (RFCOMM/SPP) transport for ELM327 on macOS
//

import Foundation
import IOBluetooth
import Combine
import OSLog
import CoreBluetooth // Only for CommProtocol signature compatibility

final class ClassicBluetoothManager: NSObject, CommProtocol {
    @Published var connectionState: ConnectionState = .disconnected
    var connectionStatePublisher: Published<ConnectionState>.Publisher { $connectionState }

    weak var obdDelegate: OBDServiceDelegate?

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.app", category: "ClassicBluetoothManager")

    // Bluetooth Classic components
    private var inquiry: IOBluetoothDeviceInquiry?
    private var device: IOBluetoothDevice?
    private var rfcommChannel: IOBluetoothRFCOMMChannel?

    // Preferences
    private let preferredName: String?
    private let preferredChannel: BluetoothRFCOMMChannelID?

    // Receive buffer and pending readers
    private let bufferQueue = DispatchQueue(label: "ClassicBT.buffer", qos: .userInitiated)
    private var receiveBuffer = Data()
    private var waitingContinuation: CheckedContinuation<String, Error>?

    // Simple completion helper for inquiry
    private var inquiryCompletion: ((Result<[IOBluetoothDevice], Error>) -> Void)?

    // Track devices we see during the inquiry in case completion reports an error
    private var discoveredDevicesDuringInquiry: [IOBluetoothDevice] = []

    // MARK: - Init

    init(preferredName: String? = nil, preferredChannel: BluetoothRFCOMMChannelID? = nil) {
        self.preferredName = preferredName
        self.preferredChannel = preferredChannel
        super.init()
    }

    // MARK: - CommProtocol

    func connectAsync(timeout: TimeInterval, peripheral _: CBPeripheral? = nil) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await self?.performInquiryAndConnect(timeout: timeout)
            }
            try await group.next()
        }
    }

    func sendCommand(_ command: String, retries: Int) async throws -> [String] {
        guard let channel = rfcommChannel else {
            throw CommunicationError.invalidData
        }

        guard let data = "\(command)\r".data(using: .ascii) else {
            throw CommunicationError.invalidData
        }

        logger.info("ClassicBT send: \(command)")

        for attempt in 1...max(retries, 1) {
            do {
                try write(data: data, on: channel)
                let response = try await waitForPrompt()
                if let lines = processResponse(response) {
                    return lines
                } else if attempt < retries {
                    logger.info("ClassicBT: no data, retrying \(attempt + 1)/\(retries)")
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                if attempt == retries {
                    throw CommunicationError.errorOccurred(error)
                }
                logger.warning("ClassicBT attempt \(attempt) failed: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        }

        throw CommunicationError.invalidData
    }

    func disconnectPeripheral() {
        if let channel = rfcommChannel {
            channel.setDelegate(nil)
            channel.close()
        }
        rfcommChannel = nil
        device = nil
        inquiry?.stop()
        inquiry?.delegate = nil
        inquiry = nil

        let old = connectionState
        connectionState = .disconnected
        if old != connectionState {
            DispatchQueue.main.async { self.obdDelegate?.connectionStateChanged(state: .disconnected) }
        }
    }

    func scanForPeripherals() async throws {
        // Fire a brief inquiry to populate recent devices; no selection UI here.
        _ = try await performInquiry(timeout: 8.0)
    }

    // MARK: - Internal

    private func performInquiryAndConnect(timeout: TimeInterval) async throws {
        if connectionState.isConnected {
            logger.info("ClassicBT already connected")
            return
        }

        let old = connectionState
        connectionState = .connecting
        if old != connectionState {
            DispatchQueue.main.async { self.obdDelegate?.connectionStateChanged(state: .connecting) }
        }

        // 1) Inquiry (main run loop)
        var foundDevices = try await performInquiry(timeout: max(timeout, 8.0))

        // Fallback to paired/recent devices if inquiry found none
        if foundDevices.isEmpty {
            let known = self.knownClassicDevices()
            if !known.isEmpty {
                logger.info("ClassicBT: using paired/recent devices fallback: \(known.count) device(s)")
                foundDevices = known
            } else {
                logger.warning("ClassicBT: no devices discovered or known")
            }
        }

        // If a preferred name was provided, try to pick that first
        if let target = pickPreferredNameDevice(from: foundDevices) {
            try await openRFCOMM(to: target, timeout: timeout)
        } else {
            // Heuristic: pick first device that exposes SPP or has a common ELM name
            guard let target = try await pickSPPDevice(from: foundDevices) else {
                throw CommunicationError.invalidData
            }
            try await openRFCOMM(to: target, timeout: timeout)
        }

        let newState = ConnectionState.connectedToAdapter
        let oldState = connectionState
        connectionState = newState
        if oldState != newState {
            DispatchQueue.main.async { self.obdDelegate?.connectionStateChanged(state: newState) }
        }
    }

    private func performInquiry(timeout: TimeInterval) async throws -> [IOBluetoothDevice] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[IOBluetoothDevice], Error>) in
            DispatchQueue.main.async {
                self.discoveredDevicesDuringInquiry.removeAll()

                let inquiry = IOBluetoothDeviceInquiry(delegate: self)
                self.inquiry = inquiry
                // Setting this to false avoids remote name requests that can cause non-success completion codes
                inquiry?.updateNewDeviceNames = false
                // Clamp to 1...48 seconds
                inquiry?.inquiryLength = UInt8(max(1, min(48, Int(ceil(timeout)))))
                self.logger.info("ClassicBT: starting inquiry for \(inquiry?.inquiryLength ?? 0)s")

                let status = inquiry?.start()
                if status != kIOReturnSuccess {
                    self.logger.error("ClassicBT: inquiry start failed: \(status ?? -1)")
                    continuation.resume(throwing: CommunicationError.invalidData)
                    return
                }

                // Will resume in delegate when complete or error.
                self.inquiryCompletion = { result in
                    switch result {
                    case .success(let devices):
                        continuation.resume(returning: devices)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func knownClassicDevices() -> [IOBluetoothDevice] {
        var results: [IOBluetoothDevice] = []

        if let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
            results.append(contentsOf: paired)
        }
        // recentDevices is available on macOS; limit to a small number
        if let recent = IOBluetoothDevice.recentDevices(10) as? [IOBluetoothDevice] {
            // Avoid duplicates by address
            let existing = Set(results.compactMap { $0.addressString })
            results.append(contentsOf: recent.filter { dev in
                guard let addr = dev.addressString else { return true }
                return !existing.contains(addr)
            })
        }

        return results
    }

    private func pickPreferredNameDevice(from devices: [IOBluetoothDevice]) -> IOBluetoothDevice? {
        guard let nameFragment = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines), !nameFragment.isEmpty else {
            return nil
        }
        let match = devices.first { dev in
            (dev.name ?? "").localizedCaseInsensitiveContains(nameFragment)
        }
        if let m = match {
            logger.info("ClassicBT: selecting preferredName match '\(m.name ?? "Unknown")'")
        } else {
            logger.info("ClassicBT: preferredName '\(nameFragment)' not found in discovered devices")
        }
        return match
    }

    private func pickSPPDevice(from devices: [IOBluetoothDevice]) async throws -> IOBluetoothDevice? {
        // Prefer devices that advertise SPP or match common ELM names
        let preferredNames = ["OBD", "ELM", "VLink", "Vgate", "OBDII", "OBD2", "OBDLink"]
        let sorted = devices.sorted { ($0.name ?? "") < ($1.name ?? "") }

        for dev in sorted {
            let name = dev.name ?? ""
            if preferredNames.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
                logger.info("ClassicBT: selecting preferred device '\(name)'")
                return dev
            }
            // Try SDP to confirm RFCOMM channel exists
            if (try? rfcommChannelID(for: dev)) != nil {
                logger.info("ClassicBT: selecting device with RFCOMM '\(name)'")
                return dev
            }
        }
        // Fallback: just return first device if any
        let fallback = sorted.first
        if let fb = fallback {
            logger.info("ClassicBT: selecting fallback device '\(fb.name ?? "Unknown")'")
        }
        return fallback
    }

    private func rfcommChannelID(for device: IOBluetoothDevice) throws -> BluetoothRFCOMMChannelID {
        // If caller provided a preferred channel, honor it immediately
        if let override = preferredChannel {
            return override
        }

        var channelID: BluetoothRFCOMMChannelID = 0
        var sppRecord: IOBluetoothSDPServiceRecord?

        // Try to find SPP service record (UUID 0x1101)
        let sppUUIDOpt = IOBluetoothSDPUUID(uuid16: 0x1101)
        let services = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        if let sppUUID = sppUUIDOpt {
            for record in services {
                if record.hasService(from: [sppUUID]) {
                    sppRecord = record
                    break
                }
            }
        }

        if sppRecord == nil {
            // Perform SDP query if services not populated
            device.performSDPQuery(nil)
            Thread.sleep(forTimeInterval: 1.0) // brief wait for SDP; production code should use delegate
        }

        if sppRecord == nil {
            let services2 = device.services as? [IOBluetoothSDPServiceRecord] ?? []
            if let sppUUID = sppUUIDOpt {
                for record in services2 {
                    if record.hasService(from: [sppUUID]) {
                        sppRecord = record
                        break
                    }
                }
            }
        }

        guard let record = sppRecord,
              record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            // Many ELM327 clones use channel 1 by convention; try that as a fallback
            channelID = 1
            return channelID
        }
        return channelID
    }

    private func openRFCOMM(to device: IOBluetoothDevice, timeout: TimeInterval) async throws {
        let channelID = try rfcommChannelID(for: device)

        var channel: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelSync(&channel, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess, let ch = channel else {
            throw CommunicationError.invalidData
        }

        rfcommChannel = ch
        self.device = device

        // Wait briefly to ensure channel is ready
        try await Task.sleep(nanoseconds: UInt64(min(max(timeout, 0.2), 2.0) * 1_000_000_000))
    }

    private func write(data: Data, on channel: IOBluetoothRFCOMMChannel) throws {
        let result = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> IOReturn in
            guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return kIOReturnError }
            // writeSync expects UnsafeMutableRawPointer; bridge from const pointer safely.
            let mutable = UnsafeMutableRawPointer(mutating: base)
            return channel.writeSync(mutable, length: UInt16(data.count))
        }
        if result != kIOReturnSuccess {
            throw CommunicationError.invalidData
        }
    }

    private func waitForPrompt() async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            bufferQueue.async {
                if self.waitingContinuation != nil {
                    continuation.resume(throwing: CommunicationError.invalidData)
                    return
                }
                self.waitingContinuation = continuation
            }
        }
    }

    private func completeIfPromptAvailable() {
        bufferQueue.async {
            guard let continuation = self.waitingContinuation else { return }
            if let str = String(data: self.receiveBuffer, encoding: .utf8), str.contains(">") {
                self.receiveBuffer.removeAll()
                self.waitingContinuation = nil
                continuation.resume(returning: str)
            }
        }
    }

    private func processResponse(_ response: String) -> [String]? {
        logger.info("ClassicBT processing: \(response)")
        var lines = response.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        if lines.last?.contains(">") == true {
            lines.removeLast()
        }

        if lines.first?.lowercased() == "no data" {
            return nil
        }

        return lines
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension ClassicBluetoothManager: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry) {
        logger.info("ClassicBT: inquiry started (length=\(sender.inquiryLength))")
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry, device: IOBluetoothDevice) {
        logger.info("ClassicBT: found device during inquiry: \(device.name ?? "Unknown") [\(device.addressString ?? "N/A")]")
        // Accumulate devices as they’re found so we can return them even if completion reports a non-success error
        if !discoveredDevicesDuringInquiry.contains(where: { $0.addressString == device.addressString }) {
            discoveredDevicesDuringInquiry.append(device)
        }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry, error: IOReturn, aborted: Bool) {
        let devices = (sender.foundDevices as? [IOBluetoothDevice]) ?? []
        logger.info("ClassicBT: inquiry complete. aborted=\(aborted), error=\(error), found=\(devices.count), seenDuringScan=\(self.discoveredDevicesDuringInquiry.count)")

        defer {
            discoveredDevicesDuringInquiry.removeAll()
            inquiryCompletion = nil
            inquiry?.delegate = nil
            inquiry = nil
        }

        if aborted {
            inquiryCompletion?(.failure(CommunicationError.invalidData))
            return
        }

        if error == kIOReturnSuccess {
            inquiryCompletion?(.success(devices))
            return
        }

        // Non-success error: if we did see devices during the scan, still return them
        if !discoveredDevicesDuringInquiry.isEmpty {
            logger.info("ClassicBT: returning devices seen during scan despite non-success completion")
            inquiryCompletion?(.success(discoveredDevicesDuringInquiry))
        } else {
            inquiryCompletion?(.failure(CommunicationError.invalidData))
        }
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension ClassicBluetoothManager: IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel, status error: IOReturn) {
        if error == kIOReturnSuccess {
            logger.info("ClassicBT RFCOMM open complete")
        } else {
            logger.error("ClassicBT RFCOMM open failed: \(error)")
            let old = connectionState
            connectionState = .error
            if old != connectionState {
                DispatchQueue.main.async { self.obdDelegate?.connectionStateChanged(state: .error) }
            }
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        logger.info("ClassicBT RFCOMM closed")
        let old = connectionState
        connectionState = .disconnected
        if old != connectionState {
            DispatchQueue.main.async { self.obdDelegate?.connectionStateChanged(state: .disconnected) }
        }
    }

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel, data dataPointer: UnsafeMutableRawPointer, length dataLength: Int) {
        let bytes = Data(bytes: dataPointer, count: dataLength)
        bufferQueue.async {
            self.receiveBuffer.append(bytes)
        }
        completeIfPromptAvailable()
    }

    func rfcommChannelControlSignalsChanged(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        // Optional: handle DTR/RTS if needed
    }

    func rfcommChannelFlowControlChanged(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        // Optional: handle flow control
    }

    func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel, refcon: UnsafeMutableRawPointer?, status error: IOReturn) {
        if error != kIOReturnSuccess {
            logger.error("ClassicBT write failed: \(error)")
        }
    }

    func rfcommChannelQueueSpaceAvailable(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        // Optional: can be used to resume writes
    }
}
