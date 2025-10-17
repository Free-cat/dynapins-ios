@testable import DynamicPinning
import XCTest

/// Tests for the CryptoService class with real ES256-signed JWS tokens.
@available(iOS 14.0, macOS 10.15, *)
final class CryptoServiceTests: XCTestCase {
    
    var cryptoService: CryptoService?
    var testKeyPair: JWSTestHelper.TestKeyPair?
    var fixedClock: FixedClock?
    
    override func setUp() {
        super.setUp()
        
        // Generate a fresh key pair for each test
        testKeyPair = JWSTestHelper.generateKeyPair()
        
        // Fixed clock at 2024-01-15 12:00:00 UTC (timestamp: 1705320000)
        fixedClock = FixedClock.at(year: 2024, month: 1, day: 15, hour: 12)
        
        // Create crypto service with fixed clock
        cryptoService = CryptoService(currentTimestamp: fixedClock!.now)
    }
    
    override func tearDown() {
        cryptoService = nil
        testKeyPair = nil
        fixedClock = nil
        super.tearDown()
    }
    
    // MARK: - Valid JWS Tests
    
    func testVerifyValidJWS() throws {
        // Given - A properly signed JWS with valid claims
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "api.example.com",
            pins: ["abc123", "def456"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When - Verifying with the correct public key
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64,
            expectedDomain: "api.example.com"
        )
        
        // Then - Payload should be decoded correctly
        XCTAssertEqual(payload.domain, "api.example.com")
        XCTAssertEqual(payload.pins, ["abc123", "def456"])
        XCTAssertEqual(payload.iat, now)
        XCTAssertEqual(payload.exp, now + 3600)
        XCTAssertEqual(payload.ttlSeconds, 3600)
    }
    
    func testVerifyJWSWithMultiplePins() throws {
        // Given - JWS with multiple pins (primary + backups)
        let now = fixedClock.now()
        let pins = [
            "pin1_primary",
            "pin2_backup1",
            "pin3_backup2"
        ]
        
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "cdn.example.com",
            pins: pins,
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 7200
        )
        
        // When
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64
        )
        
        // Then
        XCTAssertEqual(payload.pins.count, 3)
        XCTAssertEqual(payload.pins, pins)
    }
    
    func testVerifyJWSWithKid() throws {
        // Given - JWS with key ID in header
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["test_pin"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600,
            kid: "test-key-2024-01"
        )
        
        // When
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64
        )
        
        // Then
        XCTAssertEqual(payload.domain, "example.com")
    }
    
    // MARK: - Invalid Signature Tests
    
    func testVerifyJWSWithWrongPublicKey() throws {
        // Given - JWS signed with one key, but verified with another
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // Create a different key pair
        let otherKeyPair = JWSTestHelper.generateKeyPair()
        
        // When/Then - Should fail signature verification
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: otherKeyPair.publicKeyBase64
            )
        ) { error in
            guard case CryptoService.CryptoError.signatureVerificationFailed = error else {
                XCTFail("Expected signatureVerificationFailed, got \(error)")
                return
            }
        }
    }
    
    func testVerifyJWSWithTamperedPayload() throws {
        // Given - A valid JWS with tampered payload
        let now = fixedClock.now()
        var jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["original_pin"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // Tamper with the payload (change domain in base64 payload)
        let parts = jwsToken.split(separator: ".")
        if parts.count == 3 {
            let tamperedPayload = "{\"domain\":\"hacked.com\",\"pins\":[\"fake\"],\"iat\":\(now),\"exp\":\(now + 3600),\"ttl_seconds\":3600}"
                .data(using: .utf8) ?? Data()
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            jwsToken = "\(parts[0]).\(tamperedPayload).\(parts[2])"
        }
        
        // When/Then - Should fail signature verification
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: testKeyPair.publicKeyBase64
            )
        ) { error in
            guard case CryptoService.CryptoError.signatureVerificationFailed = error else {
                XCTFail("Expected signatureVerificationFailed, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Expiration Tests
    
    func testVerifyExpiredJWS() throws {
        // Given - JWS that expired 1 hour ago
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now - 7200,  // Issued 2 hours ago
            exp: now - 3600   // Expired 1 hour ago
        )
        
        // When/Then - Should throw tokenExpired
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: testKeyPair.publicKeyBase64
            )
        ) { error in
            guard case CryptoService.CryptoError.tokenExpired = error else {
                XCTFail("Expected tokenExpired, got \(error)")
                return
            }
        }
    }
    
    func testVerifyJWSExpiringInOneSecond() throws {
        // Given - JWS that expires in 1 second (should still be valid)
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now - 3599,
            exp: now + 1  // Expires in 1 second
        )
        
        // When - Should succeed (not expired yet)
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64
        )
        
        // Then
        XCTAssertEqual(payload.domain, "example.com")
    }
    
    func testVerifyJWSWithFutureIatWithinSkew() throws {
        // Given - JWS with iat 4 minutes in future (within 5 min tolerance)
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now + 240,  // 4 minutes in future (within tolerance)
            exp: now + 3840
        )
        
        // When - Should succeed (within clock skew tolerance)
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64
        )
        
        // Then
        XCTAssertEqual(payload.domain, "example.com")
    }
    
    func testVerifyJWSWithFutureIatBeyondSkew() throws {
        // Given - JWS with iat 6 minutes in future (beyond 5 min tolerance)
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now + 360,  // 6 minutes in future (beyond tolerance)
            exp: now + 3960
        )
        
        // When/Then - Should throw invalidTimestamp
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: testKeyPair.publicKeyBase64
            )
        ) { error in
            guard case CryptoService.CryptoError.invalidTimestamp = error else {
                XCTFail("Expected invalidTimestamp, got \(error)")
                return
            }
        }
    }
    
    // MARK: - Domain Validation Tests
    
    func testVerifyJWSWithMatchingDomain() throws {
        // Given - JWS for "api.example.com"
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "api.example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When - Request for the same domain
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64,
            expectedDomain: "api.example.com"
        )
        
        // Then - Should succeed
        XCTAssertEqual(payload.domain, "api.example.com")
    }
    
    func testVerifyJWSWithDomainMismatch() throws {
        // Given - JWS for "api.example.com"
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "api.example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When/Then - Request for different domain should fail
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: testKeyPair.publicKeyBase64,
                expectedDomain: "cdn.different.com"
            )
        ) { error in
            guard case CryptoService.CryptoError.domainMismatch(let expected, let actual) = error else {
                XCTFail("Expected domainMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, "cdn.different.com")
            XCTAssertEqual(actual, "api.example.com")
        }
    }
    
    func testVerifyJWSWithWildcardDomain() throws {
        // Given - JWS with wildcard domain "*.example.com"
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "*.example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When - Request for "api.example.com" (should match wildcard)
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64,
            expectedDomain: "api.example.com"
        )
        
        // Then - Should succeed
        XCTAssertEqual(payload.domain, "*.example.com")
        XCTAssertEqual(payload.pins, ["pin123"])
    }
    
    func testVerifyJWSWithWildcardDomainMismatch() throws {
        // Given - JWS with wildcard "*.example.com"
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "*.example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When/Then - Request for "other.com" should fail
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(
                jwsString: jwsToken,
                publicKey: testKeyPair.publicKeyBase64,
                expectedDomain: "other.com"
            )
        ) { error in
            guard case CryptoService.CryptoError.domainMismatch = error else {
                XCTFail("Expected domainMismatch, got \(error)")
                return
            }
        }
    }
    
    func testVerifyJWSWithCaseInsensitiveDomain() throws {
        // Given - JWS for "API.EXAMPLE.COM" (uppercase)
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "API.EXAMPLE.COM",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When - Request for "api.example.com" (lowercase) should match
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64,
            expectedDomain: "api.example.com"
        )
        
        // Then - Should succeed (case-insensitive match)
        XCTAssertEqual(payload.domain.lowercased(), "api.example.com")
    }
    
    func testVerifyJWSWithoutExpectedDomain() throws {
        // Given - JWS for any domain
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "any.domain.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        // When - Don't provide expectedDomain (domain check skipped)
        let payload = try cryptoService.verifyJWS(
            jwsString: jwsToken,
            publicKey: testKeyPair.publicKeyBase64,
            expectedDomain: nil
        )
        
        // Then - Should succeed
        XCTAssertEqual(payload.domain, "any.domain.com")
    }
    
    // MARK: - Malformed JWS Tests
    
    func testVerifyJWSWithMalformedToken() throws {
        // Given - Malformed JWS tokens
        let invalidTokens = [
            "not.a.jws",                           // Only 2 parts
            "invalid",                              // No dots
            "a.b.c.d",                             // Too many parts
            "",                                     // Empty string
            "..."                                   // Empty parts
        ]
        
        // When/Then - All should throw invalidJWSFormat
        for token in invalidTokens {
            XCTAssertThrowsError(
                try cryptoService.verifyJWS(jwsString: token, publicKey: testKeyPair.publicKeyBase64)
            ) { error in
                guard case CryptoService.CryptoError.invalidJWSFormat = error else {
                    XCTFail("Expected invalidJWSFormat for '\(token)', got \(error)")
                    return
                }
            }
        }
    }
    
    func testVerifyJWSWithInvalidPublicKey() throws {
        // Given - Valid JWS but invalid public keys
        let now = fixedClock.now()
        let jwsToken = try JWSTestHelper.createSignedFingerprint(
            domain: "example.com",
            pins: ["pin123"],
            privateKey: testKeyPair.privateKey,
            iat: now,
            exp: now + 3600
        )
        
        let invalidKeys = [
            "not_valid_base64!!!",
            "dGVzdA==",  // Too short
            ""           // Empty
        ]
        
        // When/Then - Should throw invalidPublicKey or related error
        for key in invalidKeys {
            XCTAssertThrowsError(
                try cryptoService.verifyJWS(jwsString: jwsToken, publicKey: key)
            ) { error in
                XCTAssertTrue(error is CryptoService.CryptoError, "Expected CryptoError for key '\(key)', got \(error)")
            }
        }
    }
    
    func testVerifyJWSWithInvalidAlgorithm() throws {
        // Note: JOSESwift will reject non-ES256 algorithms during parsing
        // This test documents that behavior
        
        // Given - JWS with HS256 algorithm (header: {"alg":"HS256","typ":"JWT"})
        let jwsWithWrongAlg = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwNTMyMDAwMCwiZXhwIjoxNzA1MzIzNjAwLCJ0dGxfc2Vjb25kcyI6MzYwMH0.dGVzdA"
        
        // When/Then - Should throw invalidAlgorithm or invalidJWSFormat
        XCTAssertThrowsError(
            try cryptoService.verifyJWS(jwsString: jwsWithWrongAlg, publicKey: testKeyPair.publicKeyBase64)
        ) { error in
            // Algorithm validation happens early in parsing
            XCTAssertTrue(error is CryptoService.CryptoError, "Expected CryptoError, got \(error)")
        }
    }
}
