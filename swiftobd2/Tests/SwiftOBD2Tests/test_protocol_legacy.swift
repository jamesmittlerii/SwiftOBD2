//
//  test_protocol_legacy.swift
//
//
//  Created by kemo konteh on 5/15/24.
//
@testable import SwiftOBD2
import XCTest

let LEGACY_PROTOCOLS: [CANProtocol] = [
    SaeJ1850Pwm(),
    SaeJ1850Vpw(),
    Iso91412(),
    Iso142304Kwp5Baud(),
    Iso142304KwpFast(),
]

final class test_protocol_legacy: XCTestCase {
    func test_single_frame() {
        for canprotocol in LEGACY_PROTOCOLS {
            // minimum valid length
            var data = try? canprotocol.parse(["48 6B 10 41 00 FF"]).first?.data
            XCTAssertEqual(data, Data([0x00]))

            // maximum valid length

            data = try? canprotocol.parse(["48 6B 10 41 00 00 01 02 03 04 FF"]).first?.data
            XCTAssertEqual(data, Data([0x00, 0x00, 0x01, 0x02, 0x03, 0x04]))

            // to short
            data = try? canprotocol.parse(["48 6B 10 41"]).first?.data
            XCTAssertNil(data)
        }
    }
}
