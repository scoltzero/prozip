import AppKit
import CoreFoundation
import Darwin
import FinderSync
import Foundation

public final class FinderSync: FIFinderSync {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public override init() {
        super.init()
        refreshMonitoring()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshMonitoring()
            }
            observers.append((workspaceCenter, token))
        }
        let distributed = DistributedNotificationCenter.default()
        let token = distributed.addObserver(forName: FinderMonitoringPolicy.preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshMonitoring()
        }
        observers.append((distributed, token))
    }

    deinit { for (center, token) in observers { center.removeObserver(token) } }

    public override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selected = FIFinderSyncController.default().selectedItemURLs(), !selected.isEmpty else { return nil }
        let items = selected.map { url in
            FinderSelectionItem(url: url, isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath)
        }
        let commands = FinderMenuPolicy.commands(for: items)
        guard !commands.isEmpty else { return nil }
        let menu = NSMenu(title: "ProZip")
        for command in commands {
            guard let request = try? command.requestURL() else { return nil }
            let item = NSMenuItem(title: command.title, action: #selector(performCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = request as NSURL
            menu.addItem(item)
        }
        return menu
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? URL else { return }
        _ = NSWorkspace.shared.open(request)
    }

    private func refreshMonitoring() {
        let domain = FinderMonitoringPolicy.applicationID as CFString
        CFPreferencesAppSynchronize(domain)
        let enabled = CFPreferencesCopyAppValue(FinderMonitoringPolicy.externalVolumesKey as CFString, domain) as? Bool ?? false
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        let mounted = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let volumes = mounted.compactMap { url -> FinderMonitoredVolume? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FinderMonitoredVolume(url: url, isInternal: values.volumeIsInternal ?? true,
                                         isRemovable: values.volumeIsRemovable ?? false,
                                         isLocal: values.volumeIsLocal ?? false, isBrowsable: values.volumeIsBrowsable ?? false)
        }
        FIFinderSyncController.default().directoryURLs = FinderMonitoringPolicy.directories(home: Self.userHome(), externalVolumesEnabled: enabled, volumes: volumes)
    }

    private static func userHome() -> URL {
        // A sandbox's NSHomeDirectory may name its container, not the user's Finder home.
        if let path = getpwuid(getuid())?.pointee.pw_dir { return URL(fileURLWithPath: String(cString: path), isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
