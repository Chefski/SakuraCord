import CryptoKit

public extension Digest {
    /// Lowercase hexadecimal, two characters per byte. Media cache filenames and
    /// prepared-animation keys persist this spelling, so it must not change.
    var hexString: String {
        withUnsafeBytes { bytes in
            String(unsafeUninitializedCapacity: bytes.count * 2) { buffer in
                func digit(_ nibble: UInt8) -> UInt8 { nibble < 10 ? nibble &+ 48 : nibble &+ 87 }
                var index = 0
                for byte in bytes {
                    buffer[index] = digit(byte >> 4)
                    buffer[index + 1] = digit(byte & 0x0F)
                    index += 2
                }
                return index
            }
        }
    }
}
