import Foundation
import SSZipArchive
import Just

extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    var exist: Bool {
        return FileManager().fileExists(atPath: self.path)
    }
}
struct AppVersionDec: Decodable {
    let version: String
    let url: String
}
public class AppVersion: NSObject {
    var version: String = ""
    var url: String = ""
}
extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }
    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

@objc public class CapacitorUpdater: NSObject {
    
    public var statsUrl = ""
    private var lastPathHot = ""
    private var lastPathPersist = ""
    private let basePathHot = "versions"
    private let basePathPersist = "NoCloud/ionic_built_snapshots"
    private let documentsUrl = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let libraryUrl = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!


    @objc private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    // Persistent path /var/mobile/Containers/Data/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/Library/NoCloud/ionic_built_snapshots/FOLDER
    // Hot Reload path /var/mobile/Containers/Data/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/Documents/FOLDER
    // Normal /private/var/containers/Bundle/Application/8C0C07BE-0FD3-4FD4-B7DF-90A88E12B8C3/App.app/public
    
    private func prepareFolder(source: URL) {
        if (!FileManager.default.fileExists(atPath: source.path)) {
            do {
                try FileManager.default.createDirectory(atPath: source.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("✨  Capacitor-updater: Cannot createDirectory " + source.path)
            }
        }
    }
    
    private func deleteFolder(source: URL, dest: URL) {
        do {
            try FileManager.default.removeItem(atPath: source.path)
            try FileManager.default.removeItem(atPath: dest.path)
        } catch {
            print("✨  Capacitor-updater: File not removed.")
        }
    }
    
    private func moveFolder(source: URL, dest: URL) {
        let index = source.appendingPathComponent("index.html")
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: source.path)
            if (files.count == 1 && source.appendingPathComponent(files[0]).isDirectory && !FileManager.default.fileExists(atPath: index.path)) {
                try FileManager.default.moveItem(at: source.appendingPathComponent(files[0]), to: dest)
            } else {
                try FileManager.default.moveItem(at: source, to: dest)
            }
        } catch {
            print("✨  Capacitor-updater: File not moved.")
        }
    }
    
    private func saveDownloaded(content: Data?, version: String) {
        let base = documentsUrl.appendingPathComponent(basePathHot)
        prepareFolder(source: base)
        let destZip = documentsUrl.appendingPathComponent(randomString(length: 10))
        let destUnZip = documentsUrl.appendingPathComponent(randomString(length: 10))
        let destHot = base.appendingPathComponent(version)
        if (FileManager.default.createFile(atPath: destZip.path, contents: content, attributes: nil)) {
            SSZipArchive.unzipFile(atPath: destZip.path, toDestination: destUnZip.path)
            moveFolder(source: destUnZip, dest: destHot)
            deleteFolder(source: destUnZip, dest: destZip)
        } else {
            print("✨  Capacitor-updater: File not created.")
        }
    }
    
    private func saveDownloadedPersist(content: Data?, version: String) {
        let base = libraryUrl.appendingPathComponent(basePathPersist)
        prepareFolder(source: base)
        let destZip = documentsUrl.appendingPathComponent(randomString(length: 10))
        let destUnZip = documentsUrl.appendingPathComponent(randomString(length: 10))
        let destPersist = base.appendingPathComponent(version)
        if (FileManager.default.createFile(atPath: destZip.path, contents: content, attributes: nil)) {
            SSZipArchive.unzipFile(atPath: destZip.path, toDestination: destUnZip.path)
            moveFolder(source: destUnZip, dest: destPersist)
            deleteFolder(source: destUnZip, dest: destZip)
        } else {
            print("✨  Capacitor-updater: File Persist not created.")
        }
    }

    @objc public func getLatest(url: URL) -> AppVersion? {
        let r = Just.get(url)
        if r.ok {
            let resp = try? JSONDecoder().decode(AppVersionDec.self, from: r.content!)
            let latest = AppVersion()
            if resp?.url != nil && resp?.version != nil {
                latest.url = resp!.url
                latest.version = resp!.version
                //        { version: version.name, url: res.signedURL }
                return latest
            } else {
                return nil
            }

        } else {
            print("✨  Capacitor-updater: Error get Latest", url, r.error ?? "unknow")
        }
        return nil
    }
    
    @objc public func download(url: URL) -> String? {
        print("URL " + url.path)
        let r = Just.get(url)
        if r.ok {
            let version = randomString(length: 10)
            saveDownloaded(content: r.content, version: version)
            saveDownloadedPersist(content: r.content, version: version)
            return version
        } else {
            print("✨  Capacitor-updater: Error downloading zip file", r.error ?? "unknow")
        }
        return nil
    }

    @objc public func list() -> [String] {
        let dest = documentsUrl.appendingPathComponent(basePathHot)
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: dest.path)
            return files
        } catch {
            print("✨  Capacitor-updater: No version available" + dest.path)
            return []
        }
    }
    
    @objc public func delete(version: String, versionName: String) -> Bool {
        let destHot = documentsUrl.appendingPathComponent(basePathHot).appendingPathComponent(version)
        let destPersist = documentsUrl.appendingPathComponent(basePathPersist).appendingPathComponent(version)
        do {
            try FileManager.default.removeItem(atPath: destHot.path)
        } catch {
            print("✨  Capacitor-updater: Hot Folder " + destHot.path + ", not removed.")
        }
        do {
            try FileManager.default.removeItem(atPath: destPersist.path)
        } catch {
            print("✨  Capacitor-updater: Folder " + destPersist.path + ", not removed.")
            return false
        }
        sendStats(action: "delete", version: versionName)
        return true
    }

    @objc public func set(version: String, versionName: String) -> Bool {
        let destHot = documentsUrl.appendingPathComponent(basePathHot).appendingPathComponent(version)
        let indexHot = destHot.appendingPathComponent("index.html")
        let destHotPersist = libraryUrl.appendingPathComponent(basePathPersist).appendingPathComponent(version)
        let indexPersist = destHot.appendingPathComponent("index.html")
        if (destHot.isDirectory && destHotPersist.isDirectory && indexHot.exist && indexPersist.exist) {
            UserDefaults.standard.set(destHot.path, forKey: "lastPathHot")
            UserDefaults.standard.set(destHotPersist.path, forKey: "lastPathPersist")
            UserDefaults.standard.set(versionName, forKey: "versionName")
            sendStats(action: "set", version: versionName)
            return true
        }
        sendStats(action: "set_fail", version: versionName)
        return false
    }
    
    @objc public func getLastPathHot() -> String {
        return UserDefaults.standard.string(forKey: "lastPathHot") ?? ""
    }
    
    @objc public func getVersionName() -> String {
        return UserDefaults.standard.string(forKey: "versionName") ?? ""
    }
    
    @objc public func getLastPathPersist() -> String {
        return UserDefaults.standard.string(forKey: "lastPathPersist") ?? ""
    }
    
    @objc public func reset() {
        let version = UserDefaults.standard.string(forKey: "versionName") ?? ""
        sendStats(action: "reset", version: version)
        UserDefaults.standard.set("", forKey: "lastPathHot")
        UserDefaults.standard.set("", forKey: "lastPathPersist")
        UserDefaults.standard.set("", forKey: "versionName")
        UserDefaults.standard.synchronize()
    }

    @objc func sendStats(action: String, version: String) {
        if (statsUrl == "") { return }
        DispatchQueue.main.async {
            let deviceID = UIDevice.current.identifierForVendor!.uuidString
            let versionBuild = Bundle.main.buildVersionNumber ?? ""
            let bundleIdentifier =  Bundle.main.bundleIdentifier ?? ""
            _ = Just.post(self.statsUrl,
                          json: [
                                "platform": "ios",
                                "action": action,
                                "device_id": deviceID,
                                "version_name": version,
                                "version_build": versionBuild,
                                "app_id": bundleIdentifier
                        ]
            )
            print("✨  Capacitor-updater: Stats send for " + action + ", version " + version)
        }
    }
    
}
