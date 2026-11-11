import Combine
import Foundation
import XCTest
import ProZipShared

private final class FakeFileAssociationSystem: FileAssociationSystem, @unchecked Sendable {
    let applicationBundleID: String? = "org.prozip.test"
    var isPackagedApplication = true
    private let lock = NSLock()
    private var aliases: [String: String] = [:]
    private var handlers = Dictionary(uniqueKeysWithValues: FileAssociationGroup.allExtensions.map { ("type." + $0, "org.other.archive") })
    private var requests: [(String, String)] = []
    private var queries: [String: Int] = [:]
    private var mainThreadCalls = 0
    var failTypes: Set<String> = []

    var writes: [(String, String)] { lock.lock(); defer { lock.unlock() }; return requests }
    var reads: [String: Int] { lock.lock(); defer { lock.unlock() }; return queries }
    var callsOnMain: Int { lock.lock(); defer { lock.unlock() }; return mainThreadCalls }

    func bind(_ extensions: [String], to type: String) {
        lock.lock(); defer { lock.unlock() }
        for ext in extensions { aliases[ext] = type }
        handlers[type] = "org.other.archive"
    }
    func configure(_ ext: String, handler: String?) {
        lock.lock(); defer { lock.unlock() }
        handlers[aliases[ext] ?? "type." + ext] = handler
    }
    func handler(_ ext: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return handlers[aliases[ext] ?? "type." + ext]
    }
    func contentType(forExtension ext: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if Thread.isMainThread { mainThreadCalls += 1 }
        return aliases[ext] ?? "type." + ext
    }
    func defaultHandler(forContentType type: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if Thread.isMainThread { mainThreadCalls += 1 }
        queries[type, default: 0] += 1
        return handlers[type]
    }
    func setDefaultHandler(_ identifier: String, forContentType type: String) throws {
        lock.lock(); defer { lock.unlock() }
        if Thread.isMainThread { mainThreadCalls += 1 }
        requests.append((type, identifier))
        if failTypes.contains(type) { throw CocoaError(.fileWriteNoPermission) }
        handlers[type] = identifier
    }
}

@MainActor
final class FileAssociationTests: XCTestCase {
    private func preferences(_ system: FakeFileAssociationSystem) -> (ProZipPreferences, UserDefaults, String) {
        let name = "ProZip.FileAssociationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (ProZipPreferences(defaults: defaults, fileAssociationSystem: system), defaults, name)
    }

    func testCatalogHas23GroupsAndCompleteDocumentDeclarationsWithoutPKG() throws {
        XCTAssertEqual(FileAssociationGroup.all.count, 23)
        XCTAssertEqual(FileAssociationGroup.allExtensions.count, 1228)
        XCTAssertEqual(Set(FileAssociationGroup.allExtensions).count, 1228)
        XCTAssertEqual(FileAssociationGroup.all.first { $0.id == "split" }?.extensions.count, 999)
        XCTAssertEqual(FileAssociationGroup.all.first { $0.id == "zip" }?.extensions.count, 101)
        XCTAssertEqual(FileAssociationGroup.all.first { $0.id == "rar" }?.extensions.count, 101)
        XCTAssertFalse(FileAssociationGroup.allExtensions.contains("pkg"))
        XCTAssertEqual(FileAssociationGroup.provisionalRecommendedIDs.count, 7)
        let software = Set(FileAssociationGroup.all.filter { $0.section == .softwarePackage }.map(\.id))
        XCTAssertTrue(FileAssociationGroup.provisionalRecommendedIDs.isDisjoint(with: software))
        XCTAssertEqual(FileAssociationSection.allCases.map(\.rawValue), ["常用压缩包", "单文件压缩", "磁盘映像与其他格式", "软件包（谨慎）"])
        let literalDescriptions = [
            "zip": "ZIP 与 ZIPX 压缩包", "7z": "7Z 压缩包", "split": "ZIP、7Z 等以 .001 开始的数字分卷",
            "rar": "RAR 压缩包", "cbr": "以 RAR 封装的漫画归档", "tar": "TAR 及其短扩展名变体",
            "gzip": "macOS 按末尾扩展名关联，.gz 同时覆盖 .tar.gz", "bzip2": "同时覆盖 Bzip2 文件与 .tar.bz2",
            "xz": "同时覆盖 XZ 文件与 .tar.xz", "lzma": "单文件 LZMA 压缩流", "lzip": "单文件 Lzip 压缩流",
            "dmg": "以只读方式浏览磁盘映像，并快速安装其中的 macOS 应用", "iso": "以只读方式挂载并浏览光盘与文件系统镜像",
            "cab": "Microsoft Cabinet 压缩包", "cpio": "Unix CPIO 归档", "lha": "传统 LHA 系列压缩包",
            "arj": "传统 ARJ 压缩包", "xar": "Extensible Archive 容器", "rpm": "Linux RPM 软件包容器", "msi": "Windows Installer 软件包",
            "jar": "会替代 Java 启动器；ProZip 仅预览和解压", "apk": "Android 应用软件包", "spk": "Synology 软件包"
        ]
        for group in FileAssociationGroup.all { XCTAssertEqual(group.description, literalDescriptions[group.id], group.id) }
        XCTAssertEqual(FileAssociationGroup.all.first { $0.id == "split" }?.title, "分卷压缩包")
        XCTAssertEqual(FileAssociationGroup.all.first { $0.id == "cbr" }?.title, "Comic RAR")
        let project = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: project.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let declared = types.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] }
        XCTAssertEqual(Set(declared), Set(FileAssociationGroup.allExtensions))
        XCTAssertTrue(types.allSatisfy { $0["LSHandlerRank"] as? String == "Alternate" })
    }

    func testRefreshDeduplicatesTypesOffMainAndCountsFullyAssociatedGroupsOnly() async throws {
        let system = FakeFileAssociationSystem()
        system.bind(["zip", "zipx"], to: "type.shared-zip")
        system.configure("zip", handler: system.applicationBundleID)
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        var publications = 0
        let token = preferences.objectWillChange.sink { publications += 1; XCTAssertTrue(Thread.isMainThread) }
        defer { token.cancel() }
        XCTAssertTrue(system.reads.isEmpty)
        XCTAssertTrue(system.writes.isEmpty)
        try await preferences.refreshFileAssociations()
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(system.callsOnMain, 0)
        XCTAssertEqual(system.reads["type.shared-zip"], 1)
        XCTAssertEqual(system.reads.count, 1227)
        let zip = try XCTUnwrap(preferences.fileAssociationStatuses["zip"])
        XCTAssertEqual(zip.associatedCount, 2)
        XCTAssertTrue(zip.isPartiallyAssociated)
        XCTAssertFalse(zip.isFullyAssociated)
        XCTAssertEqual(preferences.fileAssociationStatuses.values.filter(\.isFullyAssociated).count, 0)
        XCTAssertTrue(system.writes.isEmpty)
    }

    func testGroupEnableAndRestoreKeepBackupAndDoNotOverwriteAnotherCurrentHandler() async throws {
        let system = FakeFileAssociationSystem()
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        try await preferences.setFileAssociationGroups(["7z"], enabled: true)
        XCTAssertEqual(system.handler("7z"), system.applicationBundleID)
        XCTAssertEqual((defaults.dictionary(forKey: "fileAssociations.previousHandlers.v1") as? [String: String])?["type.7z"], "org.other.archive")
        let previousWrites = system.writes.count
        system.configure("7z", handler: "org.third.archive")
        try await preferences.setFileAssociationGroups(["7z"], enabled: false)
        XCTAssertEqual(system.writes.count, previousWrites)
        XCTAssertEqual(system.handler("7z"), "org.third.archive")
        try await preferences.setFileAssociationGroups(["7z"], enabled: true)
        try await preferences.setFileAssociationGroups(["7z"], enabled: false)
        XCTAssertEqual(system.handler("7z"), "org.third.archive")
        XCTAssertFalse(try XCTUnwrap(preferences.fileAssociationStatuses["7z"]).isFullyAssociated)
    }

    func testMixedOnboardingSelectionCommitsInOnePublication() async throws {
        let system = FakeFileAssociationSystem()
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        let zip = try XCTUnwrap(FileAssociationGroup.all.first { $0.id == "zip" })
        var backups: [String: String] = [:]
        for ext in zip.extensions {
            system.configure(ext, handler: system.applicationBundleID)
            backups["type." + ext] = "org.other.archive"
        }
        defaults.set(backups, forKey: "fileAssociations.previousHandlers.v1")
        var publications = 0
        let token = preferences.objectWillChange.sink { publications += 1 }
        defer { token.cancel() }
        try await preferences.applyFileAssociationChanges(["zip": false, "7z": true])
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(system.callsOnMain, 0)
        XCTAssertEqual(system.handler("zip"), "org.other.archive")
        XCTAssertEqual(system.handler("7z"), system.applicationBundleID)
        XCTAssertEqual(system.handler("apk"), "org.other.archive")
        XCTAssertEqual(preferences.fileAssociationStatuses.values.filter(\.isFullyAssociated).count, 1)
    }

    func testFailedBatchRestoresKnownHandlersAndPublishesTheRealSnapshot() async throws {
        let system = FakeFileAssociationSystem()
        system.failTypes = ["type.gzip"]
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        do {
            try await preferences.setFileAssociationGroups(["gzip"], enabled: true)
            XCTFail("The failed batch must not report success")
        } catch {}
        XCTAssertEqual(system.handler("gz"), "org.other.archive")
        XCTAssertEqual(system.handler("gzip"), "org.other.archive")
        XCTAssertEqual(preferences.fileAssociationStatuses["gzip"]?.associatedCount, 0)
    }

    func testUnrestorablePartialFailureStaysPartialAndMissingBackupNeverSelectsAnotherApp() async throws {
        let system = FakeFileAssociationSystem()
        system.configure("gz", handler: nil)
        system.failTypes = ["type.gzip"]
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        do {
            try await preferences.setFileAssociationGroups(["gzip"], enabled: true)
            XCTFail("Expected a partial failure")
        } catch {}
        let state = try XCTUnwrap(preferences.fileAssociationStatuses["gzip"])
        XCTAssertEqual(state.associatedCount, 1)
        XCTAssertTrue(state.isPartiallyAssociated)
        XCTAssertFalse(state.isFullyAssociated)
        XCTAssertEqual(system.handler("gz"), system.applicationBundleID)
        let count = system.writes.count
        do {
            try await preferences.setFileAssociation("gz", enabled: false)
            XCTFail("A missing backup must not pick an arbitrary default")
        } catch { XCTAssertTrue(error.localizedDescription.contains("原默认应用")) }
        XCTAssertEqual(system.writes.count, count)
        XCTAssertEqual(system.handler("gz"), system.applicationBundleID)
    }

    func testSharedTypesAreShownAsAdditionalImpactAndContradictoryChangesAreRejected() async throws {
        let system = FakeFileAssociationSystem()
        system.bind(["zip", "apk"], to: "type.shared")
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        try await preferences.refreshFileAssociations()
        XCTAssertTrue(preferences.additionalAssociationImpact(for: ["zip"]).contains("APK"))
        XCTAssertTrue(system.writes.isEmpty)
        do {
            try await preferences.applyFileAssociationChanges(["zip": true, "apk": false])
            XCTFail("One system type cannot be enabled and restored at the same time")
        } catch {}
        XCTAssertTrue(system.writes.isEmpty)
    }

    func testUnpackagedAdapterIsRejectedBeforeAnySystemQueryOrWrite() async throws {
        let system = FakeFileAssociationSystem()
        system.isPackagedApplication = false
        let (preferences, defaults, name) = preferences(system)
        defer { defaults.removePersistentDomain(forName: name) }
        do { try await preferences.refreshFileAssociations(); XCTFail("Expected packaged-app guard") } catch {}
        do { try await preferences.setFileAssociationGroups(["zip"], enabled: true); XCTFail("Expected packaged-app guard") } catch {}
        XCTAssertTrue(system.reads.isEmpty)
        XCTAssertTrue(system.writes.isEmpty)
        XCTAssertFalse(preferences.fileAssociationsLoaded)
    }
}
