import Foundation

/// A simple DER (Distinguished Encoding Rules) parser for extracting certificate fields.
struct DERParser {
    private let data: Data
    private var index: Int
    
    init(data: Data) {
        self.data = data
        self.index = 0
    }
    
    /// Reads a DER length value.
    mutating func readLength() -> Int? {
        guard index < data.count else { return nil }
        let firstByte = data[index]
        index += 1
        
        if firstByte & 0x80 == 0 {
            // Short form
            return Int(firstByte)
        } else {
            // Long form
            let numBytes = Int(firstByte & 0x7F)
            guard index + numBytes <= data.count else { return nil }
            
            var length = 0
            for _ in 0..<numBytes {
                length = (length << 8) | Int(data[index])
                index += 1
            }
            return length
        }
    }
    
    /// Skips a DER sequence (tag + length + content).
    mutating func skipSequence() -> Bool {
        guard index < data.count, data[index] == 0x30 else { return false }
        index += 1
        guard let length = readLength() else { return false }
        index += length
        return true
    }
    
    /// Skips a DER integer (tag + length + content).
    mutating func skipInteger() -> Bool {
        guard index < data.count, data[index] == 0x02 else { return false }
        index += 1
        guard let length = readLength() else { return false }
        index += length
        return true
    }
    
    /// Skips an optional explicit tag (e.g., version [0]).
    mutating func skipOptionalExplicit(tag: UInt8) -> Bool {
        if index < data.count && data[index] == tag {
            index += 1
            guard let length = readLength() else { return false }
            index += length
        }
        return true
    }
    
    /// Extracts a sequence starting at the current position.
    mutating func extractSequence() -> Data? {
        guard index < data.count, data[index] == 0x30 else { return nil }
        let start = index
        index += 1
        guard let length = readLength() else { return nil }
        
        let totalLength = index - start + length
        guard start + totalLength <= data.count else { return nil }
        
        return data.subdata(in: start..<(start + totalLength))
    }
}
