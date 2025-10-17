#!/usr/bin/env swift

import Foundation
import CryptoKit

// Test response from server
let jsonString = """
{
  "domain": "example.com",
  "pins": [
    "88c3292097527f95650a51dac5945eca168bc4bb2664c30d022036a4c47cfcce",
    "a814636663a69123492f4a7bd337a4ee8752233aacfe6b91e0993dc58c823fe1"
  ],
  "created": "2025-10-17T11:19:41Z",
  "expires": "2025-10-17T12:19:41Z",
  "ttl_seconds": 3600,
  "keyId": "7fda4c1e",
  "alg": "Ed25519",
  "signature": "YfgwXFSRbB4zn1r1jtoqjkiLCxajox/tsLRtHRgwXiZ8i34JnfTMWjOl/L0yyR/cjJQ85sRP78fVyeAMxWD/CA=="
}
"""

struct SignablePayload: Encodable {
    let domain: String
    let pins: [String]
    let created: String
    let expires: String
    let ttl_seconds: Int
    let keyId: String
    let alg: String
}

// Parse JSON
let jsonData = jsonString.data(using: .utf8)!
let response = try! JSONDecoder().decode([String: AnyCodable].self, from: jsonData)

// Create signable payload
let payload = SignablePayload(
    domain: response["domain"]!.value as! String,
    pins: response["pins"]!.value as! [String],
    created: response["created"]!.value as! String,
    expires: response["expires"]!.value as! String,
    ttl_seconds: response["ttl_seconds"]!.value as! Int,
    keyId: response["keyId"]!.value as! String,
    alg: response["alg"]!.value as! String
)

// Encode to JSON
let encoder = JSONEncoder()
let payloadData = try! encoder.encode(payload)
let payloadString = String(data: payloadData, encoding: .utf8)!

print("Payload to verify:")
print(payloadString)
print()
print("Hex:")
print(payloadData.map { String(format: "%02x", $0) }.joined())
print()

// Load public key from SPKI format
let publicKeyBase64 = "MCowBQYDK2VwAyEA9gocJEBHG+vcm2OH42ZEy8XiYarSBJ3ZBTA5Ni7J+Ac="
let publicKeyData = Data(base64Encoded: publicKeyBase64)!
let rawPublicKey = publicKeyData.suffix(32)

print("Public key (raw):")
print(rawPublicKey.map { String(format: "%02x", $0) }.joined())
print()

// Create verifying key
let verifyingKey = try! Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)

// Decode signature
let signatureBase64 = response["signature"]!.value as! String
let signatureData = Data(base64Encoded: signatureBase64)!

print("Signature:")
print(signatureData.map { String(format: "%02x", $0) }.joined())
print()

// Verify
let isValid = verifyingKey.isValidSignature(signatureData, for: payloadData)
print("Signature valid: \(isValid)")

// Helper for dynamic decoding
struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let stringValue as String:
            try container.encode(stringValue)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}

