import Foundation
import AppKit

struct BrowserProfile: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let bundleIdentifiers: [String]
    let bookmarksPath: String
    let appURL: URL?

    var isInstalled: Bool { appURL != nil }

    static let safariAppURL: URL? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
    static let installed: [BrowserProfile] = all.filter(\.isInstalled)

    static let all: [BrowserProfile] = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path

        func profile(_ name: String, ids: [String], path: String) -> BrowserProfile {
            let appURL = ids.lazy
                .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .first
            return BrowserProfile(name: name, bundleIdentifiers: ids, bookmarksPath: "\(support)/\(path)", appURL: appURL)
        }

        return [
            profile("Brave",          ids: ["com.brave.Browser", "com.brave.Browser.nightly"],       path: "BraveSoftware/Brave-Browser/Default/Bookmarks"),
            profile("Google Chrome",  ids: ["com.google.Chrome", "com.google.Chrome.canary"],        path: "Google/Chrome/Default/Bookmarks"),
            profile("Microsoft Edge", ids: ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta"],  path: "Microsoft Edge/Default/Bookmarks"),
            profile("Opera",          ids: ["com.operasoftware.Opera"],                              path: "com.operasoftware.Opera/Default/Bookmarks"),
            profile("Vivaldi",        ids: ["com.vivaldi.Vivaldi"],                                  path: "Vivaldi/Default/Bookmarks"),
            profile("Arc",            ids: ["company.thebrowser.Browser"],                           path: "Arc/User Data/Default/Bookmarks"),
            profile("Comet",          ids: ["ai.perplexity.comet"],                                  path: "Comet/Default/Bookmarks"),
        ]
    }()
}

enum SyncStrategy: CaseIterable, Sendable {
    case merge
    case overwrite

    var label: String {
        switch self {
        case .merge:     return String(localized: "strategy.merge", bundle: .module)
        case .overwrite: return String(localized: "strategy.overwrite", bundle: .module)
        }
    }
}

struct SyncReport: Sendable {
    let message: String
}

enum SyncError: LocalizedError, Sendable {
    case readFailure(path: String)
    case writeFailure(path: String)
    case invalidStructure(name: String)
    case browserIsOpen(name: String)
    case browserNotInstalled(name: String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .readFailure(let path):         return String(localized: "error.read.failure \(path)", bundle: .module)
        case .writeFailure(let path):        return String(localized: "error.write.failure \(path)", bundle: .module)
        case .invalidStructure(let name):    return String(localized: "error.invalid.structure \(name)", bundle: .module)
        case .browserIsOpen(let name):       return String(localized: "error.browser.open \(name)", bundle: .module)
        case .browserNotInstalled(let name): return String(localized: "error.browser.not.installed \(name)", bundle: .module)
        case .permissionDenied:              return String(localized: "error.permission.denied", bundle: .module)
        }
    }

    var recoveryURL: URL? {
        guard case .permissionDenied = self else { return nil }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}

indirect enum BookmarkNode: Equatable, Sendable {
    case url(title: String, url: String)
    case folder(name: String, children: [BookmarkNode])
}

struct SyncEngine {
    private let safariBookmarksURL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Safari/Bookmarks.plist")

    func sync(to browser: BrowserProfile, strategy: SyncStrategy) throws -> SyncReport {
        guard browser.isInstalled else { throw SyncError.browserNotInstalled(name: browser.name) }
        try assertBrowserIsClosed(browser)
        let nodes = try readSafariBookmarks()
        try writeToChromiumBrowser(nodes, to: browser, strategy: strategy)
        let verb = strategy == .overwrite
            ? String(localized: "sync.verb.overwrite", bundle: .module)
            : String(localized: "sync.verb.merge", bundle: .module)
        return SyncReport(message: String(localized: "sync.report \(browser.name) \(verb) \(nodes.totalCount)", bundle: .module))
    }

    private func assertBrowserIsClosed(_ browser: BrowserProfile) throws {
        let isRunning = browser.bundleIdentifiers.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
        if isRunning { throw SyncError.browserIsOpen(name: browser.name) }
    }

    private func readSafariBookmarks() throws -> [BookmarkNode] {
        let data = try loadSafariPlistData()
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
              let topSections = root["Children"] as? [[String: Any]] else {
            throw SyncError.invalidStructure(name: "Safari")
        }
        return topSections.flatMap(bookmarkNodes(fromSafariSection:))
    }

    private func loadSafariPlistData() throws -> Data {
        do {
            return try Data(contentsOf: safariBookmarksURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
            throw SyncError.permissionDenied
        } catch {
            throw SyncError.readFailure(path: safariBookmarksURL.path)
        }
    }

    private static let ignoredSafariSections: Set<String> = ["com.apple.ReadingList", "History", "Bookmarks"]

    private func bookmarkNodes(fromSafariSection section: [String: Any]) -> [BookmarkNode] {
        let title = section["Title"] as? String ?? ""
        guard !Self.ignoredSafariSections.contains(title),
              section["WebBookmarkType"] as? String == "WebBookmarkTypeList" else { return [] }
        let children = (section["Children"] as? [[String: Any]] ?? []).compactMap(safariNodeToBookmark)
        guard !children.isEmpty else { return [] }
        switch title {
        case "BookmarksBar":  return children
        case "BookmarksMenu": return [.folder(name: String(localized: "safari.menu.folder", bundle: .module), children: children)]
        default:              return [.folder(name: title.isEmpty ? String(localized: "unnamed.folder", bundle: .module) : title, children: children)]
        }
    }

    private func safariNodeToBookmark(_ raw: [String: Any]) -> BookmarkNode? {
        guard let type = raw["WebBookmarkType"] as? String else { return nil }
        switch type {
        case "WebBookmarkTypeLeaf":
            guard let url = raw["URLString"] as? String else { return nil }
            let title = (raw["Title"] as? String)
                ?? (raw["URIDictionary"] as? [String: Any])?["title"] as? String
                ?? url
            return .url(title: title, url: url)
        case "WebBookmarkTypeList":
            let name = (raw["Title"] as? String) ?? String(localized: "unnamed.folder", bundle: .module)
            let children = (raw["Children"] as? [[String: Any]] ?? []).compactMap(safariNodeToBookmark)
            return .folder(name: name, children: children)
        default:
            return nil
        }
    }

    private func writeToChromiumBrowser(_ nodes: [BookmarkNode], to browser: BrowserProfile, strategy: SyncStrategy) throws {
        let url = URL(fileURLWithPath: browser.bookmarksPath)
        let data = try loadChromiumBookmarksData(at: url)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var roots = root["roots"] as? [String: Any],
              var bookmarkBar = roots["bookmark_bar"] as? [String: Any] else {
            throw SyncError.invalidStructure(name: browser.name)
        }
        let existing = (bookmarkBar["children"] as? [[String: Any]] ?? []).compactMap(chromiumNodeToBookmark)
        let toWrite = strategy == .overwrite ? nodes : merge(target: existing, from: nodes)
        var idCounter = maxChromiumID(in: roots)
        bookmarkBar["children"] = toWrite.map { chromiumRaw(from: $0, idCounter: &idCounter) }
        roots["bookmark_bar"] = bookmarkBar
        root["roots"] = roots
        root["checksum"] = ""
        let serialized = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try writeAtomically(serialized, to: url)
    }

    private func loadChromiumBookmarksData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw SyncError.readFailure(path: url.path)
        }
    }

    private func chromiumNodeToBookmark(_ raw: [String: Any]) -> BookmarkNode? {
        guard let type = raw["type"] as? String else { return nil }
        switch type {
        case "url":
            guard let url = raw["url"] as? String else { return nil }
            return .url(title: (raw["name"] as? String) ?? url, url: url)
        case "folder":
            let name = (raw["name"] as? String) ?? String(localized: "unnamed.folder", bundle: .module)
            let children = (raw["children"] as? [[String: Any]] ?? []).compactMap(chromiumNodeToBookmark)
            return .folder(name: name, children: children)
        default:
            return nil
        }
    }

    private func chromiumRaw(from node: BookmarkNode, idCounter: inout Int) -> [String: Any] {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1_000_000))
        idCounter += 1
        switch node {
        case .url(let title, let url):
            return ["type": "url", "name": title, "url": url,
                    "id": String(idCounter), "guid": UUID().uuidString.lowercased(), "date_added": timestamp]
        case .folder(let name, let children):
            return ["type": "folder", "name": name,
                    "id": String(idCounter), "guid": UUID().uuidString.lowercased(),
                    "date_added": timestamp, "date_modified": timestamp,
                    "children": children.map { chromiumRaw(from: $0, idCounter: &idCounter) }]
        }
    }

    private func merge(target: [BookmarkNode], from source: [BookmarkNode]) -> [BookmarkNode] {
        var result = target
        for node in source {
            switch node {
            case .url(_, let url):
                let normalized = normalizedURL(url)
                let exists = result.contains {
                    guard case .url(_, let existing) = $0 else { return false }
                    return normalizedURL(existing) == normalized
                }
                if !exists { result.append(node) }
            case .folder(let name, let children):
                if let index = result.firstIndex(where: {
                    guard case .folder(let existing, _) = $0 else { return false }
                    return normalizedText(existing) == normalizedText(name)
                }), case .folder(let existingName, let existingChildren) = result[index] {
                    result[index] = .folder(name: existingName, children: merge(target: existingChildren, from: children))
                } else {
                    result.append(node)
                }
            }
        }
        return result
    }

    private func maxChromiumID(in roots: [String: Any]) -> Int {
        var maxID = 0
        func visit(_ node: [String: Any]) {
            if let idString = node["id"] as? String, let id = Int(idString), id > maxID { maxID = id }
            (node["children"] as? [[String: Any]] ?? []).forEach(visit)
        }
        roots.values.compactMap { $0 as? [String: Any] }.forEach(visit)
        return maxID
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let backupURL = url.deletingLastPathComponent()
            .appending(path: url.lastPathComponent + ".backup-" + timestamp())
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: .atomic)
        pruneBackups(near: url)
    }

    private func pruneBackups(near url: URL, keeping limit: Int = 5) {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".backup-"
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        backups.dropLast(limit).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func normalizedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path.hasSuffix("/"), components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }
        return components.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }

    private func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

private extension [BookmarkNode] {
    var totalCount: Int {
        reduce(0) { count, node in
            switch node {
            case .url: return count + 1
            case .folder(_, let children): return count + children.totalCount
            }
        }
    }
}
