// RAW Select – Update-Signatur (Ed25519 via CryptoKit). Läuft mit `swift tools/sign_update.swift …`.
//
// Die App öffnet ein heruntergeladenes Update nur, wenn `<dmg>.sig` zur eingebauten öffentlichen
// Schlüssel passt (AppInfo.updatePublicKey). Signiert wird NICHT nur das DMG, sondern
//   "RAWSelect-Update|<version>|<sha256-hex des DMG>"
// — so kann niemand ein altes, echt signiertes DMG unter einer höheren Versionsnummer ausliefern.
// Muss byte-gleich zu `UpdateSignature.message` in Sources/RAWSelect/Services/UpdateService.swift sein.
//
//   keygen <keyfile>                     neues Schlüsselpaar (bricht ab, falls keyfile existiert)
//   pubkey <keyfile>                     öffentlichen Schlüssel (Base64) ausgeben
//   sign   <keyfile> <dmg> <version>     schreibt <dmg>.sig und gibt die Signatur aus
//   verify <pubkey-b64> <dmg> <version> <sigfile>
//
// Der private Schlüssel liegt ausserhalb des Repos (~/.config/rawselect/update-signing.key, 0600).
// GEHT ER VERLOREN, können Nutzer ab V1.10 nicht mehr automatisch aktualisieren → sicher aufbewahren.
import CryptoKit
import Foundation

func fail(_ msg: String) -> Never { FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(1) }

func message(version: String, dmg: URL) -> Data {
    guard let data = try? Data(contentsOf: dmg, options: .mappedIfSafe) else { fail("DMG nicht lesbar: \(dmg.path)") }
    let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return Data("RAWSelect-Update|\(version)|\(hex)".utf8)
}

func loadKey(_ path: String) -> Curve25519.Signing.PrivateKey {
    guard let s = try? String(contentsOfFile: path, encoding: .utf8),
          let raw = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("Schlüssel nicht lesbar: \(path)") }
    return key
}

let a = CommandLine.arguments
guard a.count >= 3 else { fail("Aufruf: keygen|pubkey|sign|verify … (siehe Kopf der Datei)") }
switch a[1] {
case "keygen":
    let path = a[2]
    guard !FileManager.default.fileExists(atPath: path) else { fail("Existiert schon – nicht überschrieben: \(path)") }
    let key = Curve25519.Signing.PrivateKey()
    let b64 = key.rawRepresentation.base64EncodedString()
    guard FileManager.default.createFile(atPath: path, contents: Data(b64.utf8), attributes: [.posixPermissions: 0o600])
    else { fail("Konnte \(path) nicht schreiben") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "pubkey":
    print(loadKey(a[2]).publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard a.count == 5 else { fail("sign <keyfile> <dmg> <version>") }
    let dmg = URL(fileURLWithPath: a[3])
    guard let sig = try? loadKey(a[2]).signature(for: message(version: a[4], dmg: dmg)) else { fail("Signieren fehlgeschlagen") }
    let b64 = sig.base64EncodedString()
    let out = dmg.appendingPathExtension("sig")
    do { try Data(b64.utf8).write(to: out) } catch { fail("Konnte \(out.path) nicht schreiben") }
    print(b64)
case "verify":
    guard a.count == 6, let pkRaw = Data(base64Encoded: a[2]),
          let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: pkRaw),
          let sigText = try? String(contentsOfFile: a[5], encoding: .utf8),
          let sig = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines))
    else { fail("verify <pubkey-b64> <dmg> <version> <sigfile>") }
    let ok = pk.isValidSignature(sig, for: message(version: a[4], dmg: URL(fileURLWithPath: a[3])))
    print(ok ? "GÜLTIG" : "UNGÜLTIG"); exit(ok ? 0 : 1)
default:
    fail("Unbekannter Befehl: \(a[1])")
}
