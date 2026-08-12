import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encodedKey = String(data: input, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    let privateKeyData = Data(base64Encoded: encodedKey),
    let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
else {
    fputs("Invalid Sparkle private key.\n", stderr)
    exit(1)
}

print(privateKey.publicKey.rawRepresentation.base64EncodedString())
