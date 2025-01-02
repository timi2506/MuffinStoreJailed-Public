//
//  IPATool.swift
//  MuffinStoreJailed
//
//  Created by Mineek on 19/10/2024.
//

// Heavily inspired by ipatool-py.
// https://github.com/NyaMisty/ipatool-py

import Foundation
import CommonCrypto
import Zip
import SwiftUI

extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

class SHA1 {
    static func hash(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
}

extension String {
    subscript (i: Int) -> String {
        return String(self[index(startIndex, offsetBy: i)])
    }

    subscript (r: Range<Int>) -> String {
        let start = index(startIndex, offsetBy: r.lowerBound)
        let end = index(startIndex, offsetBy: r.upperBound)
        return String(self[start..<end])
    }
}

class StoreClient {
    var session: URLSession
    var appleId: String
    var password: String
    var guid: String?
    var accountName: String?
    var authHeaders: [String: String]?
    var authCookies: [HTTPCookie]?

    init(appleId: String, password: String) {
        session = URLSession.shared
        self.appleId = appleId
        self.password = password
        self.guid = nil
        self.accountName = nil
        self.authHeaders = nil
        self.authCookies = nil
    }

    func generateGuid(appleId: String) -> String {
        print("Generating GUID")
        let DEFAULT_GUID = "000C2941396B"
        let GUID_DEFAULT_PREFIX = 2
        let GUID_SEED = "CAFEBABE"
        let GUID_POS = 10

        let h = SHA1.hash((GUID_SEED + appleId + GUID_SEED).data(using: .utf8)!).hexString
        let defaultPart = DEFAULT_GUID.prefix(GUID_DEFAULT_PREFIX)
        let hashPart = h[GUID_POS..<GUID_POS + (DEFAULT_GUID.count - GUID_DEFAULT_PREFIX)]
        let guid = (defaultPart + hashPart).uppercased()

        print("Came up with GUID: \(guid)")
        return guid
    }

    func saveAuthInfo() -> Void {
        var authCookiesEnc1 = NSKeyedArchiver.archivedData(withRootObject: authCookies!)
        var authCookiesEnc = authCookiesEnc1.base64EncodedString()
        var out: [String: Any] = [
            "appleId": appleId,
            "password": password,
            "guid": guid,
            "accountName": accountName,
            "authHeaders": authHeaders,
            "authCookies": authCookiesEnc
        ]
        var data = try! JSONSerialization.data(withJSONObject: out, options: [])
        var base64 = data.base64EncodedString()
        EncryptedKeychainWrapper.saveAuthInfo(base64: base64)
    }

    func tryLoadAuthInfo() -> Bool {
        if let base64 = EncryptedKeychainWrapper.loadAuthInfo() {
            var data = Data(base64Encoded: base64)!
            var out = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
            appleId = out["appleId"] as! String
            password = out["password"] as! String
            guid = out["guid"] as? String
            accountName = out["accountName"] as? String
            authHeaders = out["authHeaders"] as? [String: String]
            var authCookiesEnc = out["authCookies"] as! String
            var authCookiesEnc1 = Data(base64Encoded: authCookiesEnc)!
            authCookies = NSKeyedUnarchiver.unarchiveObject(with: authCookiesEnc1) as? [HTTPCookie]
            print("Loaded auth info")
            return true
        }
        print("No auth info found, need to authenticate")
        return false
    }

    func authenticate(requestCode: Bool = false) -> Bool {
        if self.guid == nil {
            self.guid = generateGuid(appleId: appleId)
        }

        var req = [
            "appleId": appleId,
            "password": password,
            "guid": guid!,
            "rmp": "0",
            "why": "signIn"
        ]

        var url = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [
            "Accept": "*/*",
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
        ]

        var ret = false
        
        for attempt in 1...4 {
            req["attempt"] = String(attempt)
            request.httpBody = try! JSONSerialization.data(withJSONObject: req, options: [])
            let datatask = session.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    print("error 1 \(error.localizedDescription)")
                    return
                }
                if let response = response {
//                    print("Response: \(response)")
                    if let response = response as? HTTPURLResponse {
                        print("New URL: \(response.url!)")
                        request.url = response.url
                    }
                }
                if let data = data {
                    do {
                        let resp = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
                        if resp["m-allowed"] as! Bool {
                            print("Authentication successful")
                            var download_queue_info = resp["download-queue-info"] as! [String: Any]
                            var dsid = download_queue_info["dsid"] as! Int
                            var httpResp = response as! HTTPURLResponse
                            var storeFront = httpResp.value(forHTTPHeaderField: "x-set-apple-store-front")
                            print("Store front: \(storeFront!)")
                            self.authHeaders = [
                                "X-Dsid": String(dsid),
                                "iCloud-Dsid": String(dsid),
                                "X-Apple-Store-Front": storeFront!,
                                "X-Token": resp["passwordToken"] as! String
                            ]
                            self.authCookies = self.session.configuration.httpCookieStorage?.cookies
                            var accountInfo = resp["accountInfo"] as! [String: Any]
                            var address = accountInfo["address"] as! [String: String]
                            self.accountName = address["firstName"]! + " " + address["lastName"]!
                            self.saveAuthInfo()
                            ret = true
                        } else {
                            print("Authentication failed: \(resp["customerMessage"] as! String)")
                        }
                    } catch {
                        print("Error: \(error)")
                    }
                }
            }
            datatask.resume()
            while datatask.state != .completed {
                sleep(1)
            }
            if ret {
                break
            }
            if requestCode {
                ret = false
                break
            }
        }
        return ret
    }

    func volumeStoreDownloadProduct(appId: String, appVerId: String = "") -> [String: Any] {
        var req = [
            "creditDisplay": "",
            "guid": self.guid!,
            "salableAdamId": appId,
        ]
        if appVerId != "" {
            req["externalVersionId"] = appVerId
        }
        var url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(self.guid!)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = [
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"
        ]
        request.httpBody = try! JSONSerialization.data(withJSONObject: req, options: [])
        print("Setting headers")
        for (key, value) in self.authHeaders! {
            print("Setting header \(key): \(value)")
            request.addValue(value, forHTTPHeaderField: key)
        }
        print("Setting cookies")
        self.session.configuration.httpCookieStorage?.setCookies(self.authCookies!, for: url, mainDocumentURL: nil)

        var resp = [String: Any]()
        let datatask = session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("error 2 \(error.localizedDescription)")
                return
            }
            if let data = data {
                do {
                    print("Got response")
                    let resp1 = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as! [String: Any]
                    if resp1["cancel-purchase-batch"] != nil {
                        print("Failed to download product: \(resp1["customerMessage"] as! String)")
                    }
                    resp = resp1
                } catch {
                    print("Error: \(error)")
                }
            }
        }
        datatask.resume()
        while datatask.state != .completed {
            sleep(1)
        }
        print("Got download response")
        return resp
    }

    func download(appId: String, appVer: String = "", isRedownload: Bool = false) -> [String: Any] {
        return self.volumeStoreDownloadProduct(appId: appId, appVerId: appVer)
    }

    func downloadToPath(url: String, path: String) -> Void {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "GET"
        let datatask = session.dataTask(with: req) { (data, response, error) in
            if let error = error {
                print("error 3 \(error.localizedDescription)")
                return
            }
            if let data = data {
                do {
                    try data.write(to: URL(fileURLWithPath: path))
                } catch {
                    print("Error: \(error)")
                }
            }
        }
        datatask.resume()
        while datatask.state != .completed {
            sleep(1)
        }
        print("Downloaded to \(path)")
    }
}

class IPATool {
    @AppStorage("Downgrade Progress") var downgradeProgress = 0.1
    var session: URLSession
    var appleId: String
    var password: String
    var storeClient: StoreClient

    init(appleId: String, password: String) {
        print("init!")
        session = URLSession.shared
        self.appleId = appleId
        self.password = password
        storeClient = StoreClient(appleId: appleId, password: password)
    }

    func authenticate(requestCode: Bool = false) -> Bool {
        print("Authenticating to iTunes Store...")
        if !storeClient.tryLoadAuthInfo() {
            return storeClient.authenticate(requestCode: requestCode)
        } else {
            return true
        }
    }

    func getVersionIDList(appId: String) -> [String] {
        print("Retrieving download info for appId \(appId)")
        var downResp = storeClient.download(appId: appId, isRedownload: true)
        var songList = downResp["songList"] as! [[String: Any]]
        if songList.count == 0 {
            print("Failed to get app download info!")
            return []
        }
        var downInfo = songList[0]
        var metadata = downInfo["metadata"] as! [String: Any]
        var appVerIds = metadata["softwareVersionExternalIdentifiers"] as! [Int]
        print("Got available version ids \(appVerIds)")
        return appVerIds.map { String($0) }
    }

    func downloadIPAForVersion(appId: String, appVerId: String) -> String {
        print("Downloading IPA for app \(appId) version \(appVerId)")
        var downResp = storeClient.download(appId: appId, appVer: appVerId)
        var songList = downResp["songList"] as! [[String: Any]]
        if songList.count == 0 {
            print("Failed to get app download info!")
            return ""
        }
        var downInfo = songList[0]
        var url = downInfo["URL"] as! String
        print("Got download URL: \(url)")

        var fm = FileManager.default
        var tempDir = fm.temporaryDirectory
        var path = tempDir.appendingPathComponent("app.ipa").path
        if fm.fileExists(atPath: path) {
            print("Removing existing file at \(path)")
            try! fm.removeItem(atPath: path)
        }
        storeClient.downloadToPath(url: url, path: path)
        Zip.addCustomFileExtension("ipa")
        sleep(3)
        let path3 = URL(string: path)!
        let fileExtension = path3.pathExtension
        let fileName = path3.lastPathComponent
        let directoryName = fileName.replacingOccurrences(of: ".\(fileExtension)", with: "")
        let documentsUrl = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationUrl = documentsUrl.appendingPathComponent(directoryName, isDirectory: true)
        if fm.fileExists(atPath: destinationUrl.path) {
            print("Removing existing folder at \(destinationUrl.path)")
            try! fm.removeItem(at: destinationUrl)
        }
        
        let unzipDirectory = try! Zip.quickUnzipFile(URL(string: path)!)
        var metadata = downInfo["metadata"] as! [String: Any]
        var metadataPath = unzipDirectory.appendingPathComponent("iTunesMetadata.plist").path
        metadata["apple-id"] = appleId
        metadata["userName"] = appleId
        try! (metadata as NSDictionary).write(toFile: metadataPath, atomically: true)
        print("Wrote iTunesMetadata.plist")
        var appContentDir = ""
        let payloadDir = unzipDirectory.appendingPathComponent("Payload")
        for entry in try! fm.contentsOfDirectory(atPath: payloadDir.path) {
            if entry.hasSuffix(".app") {
                print("Found app content dir: \(entry)")
                appContentDir = "Payload/" + entry
                break
            }
        }
        print("Found app content dir: \(appContentDir)")

        var scManifestData = try! Data(contentsOf: unzipDirectory.appendingPathComponent(appContentDir).appendingPathComponent("SC_Info").appendingPathComponent("Manifest.plist"))
        var scManifest = try! PropertyListSerialization.propertyList(from: scManifestData, options: [], format: nil) as! [String: Any]
        var sinfsDict = downInfo["sinfs"] as! [[String: Any]]
        if let sinfPaths = scManifest["SinfPaths"] as? [String] {
            for (i, sinfPath) in sinfPaths.enumerated() {
                let sinfData = sinfsDict[i]["sinf"] as! Data
                try! sinfData.write(to: unzipDirectory.appendingPathComponent(appContentDir).appendingPathComponent(sinfPath))
                print("Wrote sinf to \(sinfPath)")
                downgradeProgress = 0.5

            }
        } else {
            print("Manifest.plist does not exist! Assuming it is an old app without one...")
            var infoListData = try! Data(contentsOf: unzipDirectory.appendingPathComponent(appContentDir).appendingPathComponent("Info.plist"))
            var infoList = try! PropertyListSerialization.propertyList(from: infoListData, options: [], format: nil) as! [String: Any]
            var sinfPath = appContentDir + "/SC_Info/" + (infoList["CFBundleExecutable"] as! String) + ".sinf"
            let sinfData = sinfsDict[0]["sinf"] as! Data
            try! sinfData.write(to: unzipDirectory.appendingPathComponent(sinfPath))
            print("Wrote sinf to \(sinfPath)")
            downgradeProgress = 0.5

        }
        print("Downloaded IPA to \(unzipDirectory.path)")
        downgradeProgress = 0.75
        return unzipDirectory.path

    }
}

class EncryptedKeychainWrapper {
    static func generateAndStoreKey() -> Void {
        self.deleteKey()
        print("Generating key")
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: "dev.mineek.muffinstorejailed.key",
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    [.privateKeyUsage, .biometryAny],
                    nil
                )!
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(query as CFDictionary, &error) else {
            print("Failed to generate key!!")
            return
        }
        print("Generated key!")
        print("Getting public key")
        let pubKey = SecKeyCopyPublicKey(privateKey)!
        print("Got public key")
        let pubKeyData = SecKeyCopyExternalRepresentation(pubKey, &error)! as Data
        let pubKeyBase64 = pubKeyData.base64EncodedString()
        print("Public key: \(pubKeyBase64)")
    }

    static func deleteKey() -> Void {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "dev.mineek.muffinstorejailed.key"
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveAuthInfo(base64: String) -> Void {
        let fm = FileManager.default
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "dev.mineek.muffinstorejailed.key",
            kSecReturnRef as String: true
        ]
        var keyRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &keyRef)
        if status != errSecSuccess {
            print("Failed to get key!")
            return
        }
        print("Got key!")
        let key = keyRef as! SecKey
        print("Getting public key")
        let pubKey = SecKeyCopyPublicKey(key)!
        print("Got public key")
        print("Encrypting data")
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(pubKey, .eciesEncryptionCofactorVariableIVX963SHA256AESGCM, base64.data(using: .utf8)! as CFData, &error) else {
            print("Failed to encrypt data!")
            return
        }
        print("Encrypted data")
        let path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("authinfo").path
        fm.createFile(atPath: path, contents: encryptedData as Data, attributes: nil)
        print("Saved encrypted auth info")
    }

    static func loadAuthInfo() -> String? {
        let fm = FileManager.default
        let path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("authinfo").path
        if !fm.fileExists(atPath: path) {
            return nil
        }
        let data = fm.contents(atPath: path)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "dev.mineek.muffinstorejailed.key",
            kSecReturnRef as String: true
        ]
        var keyRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &keyRef)
        if status != errSecSuccess {
            print("Failed to get key!")
            return nil
        }
        print("Got key!")
        let key = keyRef as! SecKey
        let privKey = key
        print("Decrypting data")
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(privKey, .eciesEncryptionCofactorVariableIVX963SHA256AESGCM, data as CFData, &error) else {
            print("Failed to decrypt data!")
            return nil
        }
        print("Decrypted data")
        return String(data: decryptedData as Data, encoding: .utf8)
    }

    static func deleteAuthInfo() -> Void {
        let fm = FileManager.default
        let path = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("authinfo").path
        try! fm.removeItem(atPath: path)
    }

    static func hasAuthInfo() -> Bool {
        return loadAuthInfo() != nil
    }

    static func getAuthInfo() -> [String: Any]? {
        if let base64 = loadAuthInfo() {
            var data = Data(base64Encoded: base64)!
            var out = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
            return out
        }
        return nil
    }

    static func nuke() -> Void {
        deleteAuthInfo()
        deleteKey()
    }
}
