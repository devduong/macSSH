//
//  FinderMountManager.swift
//  macSSH
//
//  Manages mounting remote FTP/FTPS/SFTP servers as Read-Write Finder volumes
//  via local loopback WebDAV Class 2 bridge + /sbin/mount_webdav -S.
//  Guarantees clean automatic unmounting on disconnect, Finder eject, app quit, or crash.
//

import Foundation
import AppKit
import Combine
import Darwin
import dnssd

/// Registers a strictly loopback-only (`lo0` -> 127.0.0.1) Bonjour `.local` hostname
/// via Apple's native mDNSResponder (`DNSServiceRegisterRecord`) without requiring root
/// or modifying `/etc/hosts`. Automatically disappears when stopped or if the app crashes.
nonisolated final class LocalBonjourHost: @unchecked Sendable {
    let hostname: String
    private let lock = NSLock()
    private var sdRef: DNSServiceRef?
    private let queue = DispatchQueue(label: "dev.duong.macSSH.LocalBonjourHost", qos: .utility)

    private static let registerReply: DNSServiceRegisterRecordReply = { _, _, _, _, _ in }

    private init(hostname: String, sdRef: DNSServiceRef) {
        self.hostname = hostname
        self.sdRef = sdRef
    }

    deinit {
        stop()
    }

    static func register(preferredName: String) -> LocalBonjourHost? {
        let label = sanitizeDNSLabel(preferredName)
        let candidates: [String] = resolvesToExternalHost(label)
            ? ["\(label).local"]
            : [label, "\(label).local"]

        for candidate in candidates {
            if let host = registerCandidate(candidate) {
                return host
            }
        }
        return nil
    }

    private static func registerCandidate(_ hostname: String) -> LocalBonjourHost? {
        var connectionRef: DNSServiceRef?
        guard DNSServiceCreateConnection(&connectionRef) == kDNSServiceErr_NoError,
              let sdRef = connectionRef else {
            return nil
        }

        let host = LocalBonjourHost(hostname: hostname, sdRef: sdRef)
        DNSServiceSetDispatchQueue(sdRef, host.queue)

        var recordRef: DNSRecordRef?
        var loopbackIP = inet_addr("127.0.0.1")
        let loIndex = if_nametoindex("lo0")
        let err = DNSServiceRegisterRecord(
            sdRef,
            &recordRef,
            DNSServiceFlags(kDNSServiceFlagsShared),
            loIndex,
            hostname,
            UInt16(kDNSServiceType_A),
            UInt16(kDNSServiceClass_IN),
            4,
            &loopbackIP,
            60,
            registerReply,
            nil
        )

        guard err == kDNSServiceErr_NoError else {
            host.stop()
            return nil
        }

        // Wait briefly (up to 450ms) for mDNSResponder to serve the new lo0 A record
        for _ in 0..<15 {
            if resolvesToLoopback(hostname) {
                return host
            }
            usleep(30_000)
        }

        host.stop()
        return nil
    }

    func stop() {
        lock.lock()
        let ref = sdRef
        sdRef = nil
        lock.unlock()
        if let ref {
            DNSServiceRefDeallocate(ref)
        }
    }

    static func sanitizeDNSLabel(_ name: String) -> String {
        let pre = name
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))

        var result = ""
        var lastWasDash = false
        for scalar in pre.unicodeScalars {
            let v = scalar.value
            let isAlphaNum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
            if isAlphaNum {
                result.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash && !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        while result.hasSuffix("-") {
            result.removeLast()
        }
        if result.count > 55 {
            result = String(result.prefix(55)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return result.isEmpty ? "macssh-server" : result
    }

    private static func resolvesToLoopback(_ host: String) -> Bool {
        resolveIPv4(host) == "127.0.0.1"
    }

    private static func resolvesToExternalHost(_ host: String) -> Bool {
        guard let ip = resolveIPv4(host) else { return false }
        return ip != "127.0.0.1"
    }

    private static func resolveIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, nil, &hints, &res)
        guard rc == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var buf = [CChar](repeating: 0, count: 64)
        let nameRC = getnameinfo(
            first.pointee.ai_addr,
            first.pointee.ai_addrlen,
            &buf,
            socklen_t(buf.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        return nameRC == 0 ? String(cString: buf) : nil
    }
}

struct MountedDriveInfo: Identifiable, Sendable {
    var id: UUID { connectionId }
    let connectionId: UUID
    let connectionName: String
    let connectionType: ConnectionType
    let volumeName: String
    let mountPointURL: URL
    let initialOpenURL: URL
    let localPort: Int
    let mountedAt: Date
}

@MainActor
final class FinderMountManager: ObservableObject {
    static let shared = FinderMountManager()

    @Published private(set) var mountedDrives: [UUID: MountedDriveInfo] = [:]
    @Published private(set) var mountingIds: Set<UUID> = []
    @Published private(set) var unmountingIds: Set<UUID> = []

    private struct ActiveMountRecord {
        let info: MountedDriveInfo
        let connection: Connection
        let password: String
        var session: SFTPSessionProtocol
        let bridge: WebDAVBridge
        let server: WebDAVHTTPServer
        let bonjourHost: LocalBonjourHost?
    }

    private var records: [UUID: ActiveMountRecord] = [:]
    private var unmountObserver: NSObjectProtocol?
    private var internetObserver: NSObjectProtocol?

    // Nonisolated emergency registry for synchronous termination / atexit fallback
    nonisolated private static let emergencyLock = NSLock()
    nonisolated(unsafe) private static var emergencyMountPaths: [UUID: String] = [:]
    nonisolated(unsafe) private static var emergencyServers: [UUID: WebDAVHTTPServer] = [:]
    nonisolated(unsafe) private static var emergencyBonjourHosts: [UUID: LocalBonjourHost] = [:]

    private init() {
        setupObservers()
        Self.setupAtexitCleanup()
    }

    // MARK: - Public Queries

    func isMounted(_ connectionId: UUID) -> Bool {
        mountedDrives[connectionId] != nil
    }

    func isMounting(_ connectionId: UUID) -> Bool {
        mountingIds.contains(connectionId)
    }

    func isUnmounting(_ connectionId: UUID) -> Bool {
        unmountingIds.contains(connectionId)
    }

    func mountInfo(for connectionId: UUID) -> MountedDriveInfo? {
        mountedDrives[connectionId]
    }

    // MARK: - Mount / Open / Unmount

    func mount(connection: Connection, password: String, openFinderWindow: Bool = true) async throws {
        guard connection.connectionType.supportsFinderMount else {
            throw AppError.sftpOperationFailed("Finder mount is supported for FTP and SFTP connections.")
        }

        if let existing = mountedDrives[connection.id] {
            if openFinderWindow {
                openURLInFinder(existing.initialOpenURL, fallback: existing.mountPointURL)
            }
            return
        }

        guard !mountingIds.contains(connection.id) else { return }
        mountingIds.insert(connection.id)
        defer { mountingIds.remove(connection.id) }

        logInfo("[FinderMount] Connecting \(connection.connectionType.badgeName) session for '\(connection.name)'...", category: .sftp)

        // 1. Create and connect dedicated session for Finder mount
        let session = try await Self.createConnectedSession(for: connection, password: password)

        // Determine initial subfolder (e.g. home dir for SFTP or subpath for FTP)
        let remoteCurrentPath = await session.currentPath

        // 2. Prepare clean mount point & unique volume name under ~/Library/Application Support/macSSH/Mounts/<name>
        let baseMountsDir = Self.mountsBaseDirectory()
        let desiredVolumeName = Self.sanitizeVolumeName(connection.name)
        let mountPointURL = allocateUniqueMountPoint(baseDir: baseMountsDir, preferredName: desiredVolumeName)
        let volumeName = mountPointURL.lastPathComponent

        // 3. Start local WebDAV Class 2 loopback bridge & NIO HTTP server
        let mountId = UUID().uuidString
        let urlSlug = LocalBonjourHost.sanitizeDNSLabel(volumeName)
        let urlPrefix = "/\(urlSlug)-\(mountId.prefix(6).lowercased())"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macSSH_WebDAV", isDirectory: true)
            .appendingPathComponent(mountId, isDirectory: true)

        let bridge = WebDAVBridge(
            session: session,
            connectionType: connection.connectionType,
            urlPrefix: urlPrefix,
            mountTempDir: tempDir
        )

        let server = WebDAVHTTPServer(tempDirectory: tempDir) { request in
            await bridge.handle(request)
        }

        let port: Int
        do {
            port = try await server.start()
        } catch {
            await bridge.cleanup()
            await session.disconnect()
            throw AppError.connectionFailed("Could not start local WebDAV loopback server: \(error.localizedDescription)")
        }

        do {
            try FileManager.default.createDirectory(at: mountPointURL, withIntermediateDirectories: true)
        } catch {
            await server.stop()
            await bridge.cleanup()
            await session.disconnect()
            throw AppError.connectionFailed("Failed to create mount directory: \(error.localizedDescription)")
        }

        // 4. Register loopback-only Bonjour hostname (<ConnectionName>.local -> 127.0.0.1 on lo0)
        // so Finder Sidebar displays the server name instead of raw "127.0.0.1".
        let bonjourHost: LocalBonjourHost? = await Task.detached(priority: .userInitiated) {
            LocalBonjourHost.register(preferredName: volumeName)
        }.value
        let mountHost = bonjourHost?.hostname ?? "127.0.0.1"

        // 5. Mount via /sbin/mount_webdav -S -o browse (auto-unmounts immediately on server loss)
        let webdavURLString = "http://\(mountHost):\(port)\(urlPrefix)/"
        do {
            try await Self.runMountWebDAV(
                volumeName: volumeName,
                webdavURL: webdavURLString,
                mountPointPath: mountPointURL.path
            )
        } catch {
            bonjourHost?.stop()
            Self.unmountPathSync(mountPointURL.path)
            if !Self.isPathCurrentlyMounted(mountPointURL.path) {
                Darwin.rmdir(mountPointURL.path)
            }
            await server.stop()
            await bridge.cleanup()
            await session.disconnect()
            throw error
        }

        // Resolve initial Finder window target (e.g. SFTP home directory or FTP subpath)
        let initialOpenURL: URL
        if remoteCurrentPath != "/" && remoteCurrentPath.hasPrefix("/") {
            let relative = String(remoteCurrentPath.dropFirst())
            let candidate = mountPointURL.appendingPathComponent(relative)
            initialOpenURL = candidate
        } else {
            initialOpenURL = mountPointURL
        }

        let info = MountedDriveInfo(
            connectionId: connection.id,
            connectionName: connection.name,
            connectionType: connection.connectionType,
            volumeName: volumeName,
            mountPointURL: mountPointURL,
            initialOpenURL: initialOpenURL,
            localPort: port,
            mountedAt: Date()
        )

        records[connection.id] = ActiveMountRecord(
            info: info,
            connection: connection,
            password: password,
            session: session,
            bridge: bridge,
            server: server,
            bonjourHost: bonjourHost
        )
        mountedDrives[connection.id] = info
        Self.registerEmergency(id: connection.id, mountPath: mountPointURL.path, server: server, bonjourHost: bonjourHost)

        logSuccess("[FinderMount] Mounted '\(connection.name)' (\(connection.connectionType.badgeName)) as '\(mountHost)' at \(mountPointURL.path) [WebDAV :\(port)]", category: .sftp)

        ToastManager.shared.show(
            title: L10n.tr("mounted_in_finder"),
            message: "\(connection.name) → \(volumeName)",
            type: .success,
            duration: 4.0
        )

        if openFinderWindow {
            openURLInFinder(initialOpenURL, fallback: mountPointURL)
        }
    }

    func openInFinder(connectionId: UUID) {
        guard let info = mountedDrives[connectionId] else { return }
        openURLInFinder(info.initialOpenURL, fallback: info.mountPointURL)
    }

    /// Automatically mounts an FTP connection in Finder when connecting if `autoMount` is enabled.
    func autoMountOnConnectIfEnabled(for connection: Connection, password: String) async {
        guard connection.connectionType.supportsAutoMount, connection.autoMount else { return }
        guard !isMounted(connection.id), !isMounting(connection.id) else { return }
        do {
            try await mount(connection: connection, password: password, openFinderWindow: false)
            logSuccess("[AutoMount] Mounted '\(connection.name)' in Finder", category: .sftp)
        } catch {
            logError("[AutoMount] Failed for '\(connection.name)': \(error.localizedDescription)", category: .network)
            ToastManager.shared.show(
                title: L10n.tr("finder_mount_failed"),
                message: "\(connection.name): \(AppError.from(error).localizedDescription)",
                type: .error,
                duration: 5.0
            )
        }
    }

    func unmount(connectionId: UUID, showToast: Bool = true) async {
        guard let record = records.removeValue(forKey: connectionId) else {
            mountedDrives.removeValue(forKey: connectionId)
            Self.unregisterEmergency(id: connectionId)
            return
        }

        unmountingIds.insert(connectionId)
        mountedDrives.removeValue(forKey: connectionId)
        defer { unmountingIds.remove(connectionId) }

        let mountPath = record.info.mountPointURL.path
        Self.unregisterEmergency(id: connectionId)

        // 1. Unmount from OS first while WebDAV server is still responsive so umount exits immediately
        await Task.detached(priority: .userInitiated) {
            Self.unmountPathSync(mountPath)
        }.value

        // 2. Tear down local WebDAV server, Bonjour host alias, cache, and remote session
        await record.server.stop()
        record.bonjourHost?.stop()
        await record.bridge.cleanup()
        await record.session.disconnect()

        // 3. Remove empty mount directory
        Self.removeMountDirectoryIfEmptyOrSafe(record.info.mountPointURL)

        logInfo("[FinderMount] Unmounted '\(record.info.connectionName)' from \(mountPath)", category: .sftp)

        if showToast {
            ToastManager.shared.show(
                title: L10n.tr("finder_unmounted"),
                message: record.info.connectionName,
                type: .info,
                duration: 3.0
            )
        }
    }

    func unmountAll() async {
        let ids = Array(records.keys)
        guard !ids.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { @MainActor in
                    await self.unmount(connectionId: id, showToast: false)
                }
            }
        }
    }

    // MARK: - Emergency & Startup Cleanup

    nonisolated static func emergencyUnmountAllSync() {
        emergencyLock.lock()
        let paths = Array(emergencyMountPaths.values)
        let servers = Array(emergencyServers.values)
        let bonjourHosts = Array(emergencyBonjourHosts.values)
        emergencyMountPaths.removeAll()
        emergencyServers.removeAll()
        emergencyBonjourHosts.removeAll()
        emergencyLock.unlock()

        for path in paths {
            unmountPathSync(path)
            if !isPathCurrentlyMounted(path) {
                Darwin.rmdir(path)
            }
        }
        for server in servers {
            server.stopSync()
        }
        for host in bonjourHosts {
            host.stop()
        }
    }

    nonisolated static func cleanupOrphanMounts() {
        DispatchQueue.global(qos: .utility).async {
            performOrphanCleanup()
        }
    }

    nonisolated static func cleanupOrphanMountsAndWait() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                performOrphanCleanup()
                continuation.resume()
            }
        }
    }

    nonisolated private static func performOrphanCleanup() {
        let baseDir = mountsBaseDirectory()
        let basePath = baseDir.standardizedFileURL.path

        // 1. Unmount any active OS webdav mounts residing inside macSSH/Mounts
        let currentlyMounted = listCurrentWebDAVMounts(under: basePath)
        for mountPath in currentlyMounted {
            unmountPathSync(mountPath)
        }

        // 2. Remove stale mount subdirectories that are no longer mount points (rmdir only removes empty directories)
        if let contents = try? FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) {
            for url in contents {
                if !isPathCurrentlyMounted(url.path) {
                    Darwin.rmdir(url.path)
                }
            }
        }

        // 3. Remove orphaned WebDAV temp staging/cache folders
        let webdavTmp = FileManager.default.temporaryDirectory.appendingPathComponent("macSSH_WebDAV", isDirectory: true)
        if FileManager.default.fileExists(atPath: webdavTmp.path) {
            try? FileManager.default.removeItem(at: webdavTmp)
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            let devicePath = notification.userInfo?["NSDevicePath"] as? String

            Task { @MainActor in
                await self.handleExternalUnmount(volumeURL: volumeURL, devicePath: devicePath)
            }
        }

        internetObserver = NotificationCenter.default.addObserver(
            forName: .internetStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let connected = notification.userInfo?["connected"] as? Bool ?? false
            Task { @MainActor in
                await self.handleInternetStatusChanged(connected: connected)
            }
        }
    }

    private func handleExternalUnmount(volumeURL: URL?, devicePath: String?) async {
        let candidatePaths = Set([
            volumeURL?.standardizedFileURL.path,
            volumeURL.map { Self.canonicalPath($0.path) },
            devicePath,
            devicePath.map { Self.canonicalPath($0) }
        ].compactMap { $0 })

        guard !candidatePaths.isEmpty else { return }

        let matchingIds = records.compactMap { id, record -> UUID? in
            let p1 = record.info.mountPointURL.standardizedFileURL.path
            let p2 = Self.canonicalPath(record.info.mountPointURL.path)
            if candidatePaths.contains(p1) || candidatePaths.contains(p2) {
                return id
            }
            return nil
        }

        for id in matchingIds {
            logInfo("[FinderMount] Detected Finder eject for mount \(id), cleaning up local WebDAV bridge...", category: .sftp)
            await unmount(connectionId: id, showToast: false)
        }
    }

    private func handleInternetStatusChanged(connected: Bool) async {
        guard !records.isEmpty else { return }
        if !connected {
            logWarning("[FinderMount] Internet connection lost while \(records.count) Finder volume(s) remain mounted.", category: .network)
            return
        }

        logInfo("[FinderMount] Internet restored — refreshing underlying sessions for \(records.count) Finder volume(s)...", category: .network)
        let activeIds = Array(records.keys)
        for id in activeIds {
            guard var record = records[id] else { continue }
            do {
                let newSession = try await Self.createConnectedSession(for: record.connection, password: record.password)
                let oldSession = record.session
                await record.bridge.replaceSession(newSession)
                record.session = newSession
                records[id] = record
                await oldSession.disconnect()
                logSuccess("[FinderMount] Restored remote session for mounted volume '\(record.info.connectionName)'.", category: .network)
            } catch {
                logWarning("[FinderMount] Failed to refresh remote session for '\(record.info.connectionName)': \(error.localizedDescription)", category: .network)
            }
        }
    }

    // MARK: - Helpers

    private func openURLInFinder(_ url: URL, fallback: URL) {
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func allocateUniqueMountPoint(baseDir: URL, preferredName: String) -> URL {
        let usedNames = Set(mountedDrives.values.map { $0.mountPointURL.lastPathComponent })
        var candidateName = preferredName
        var suffix = 2

        while usedNames.contains(candidateName) || Self.isPathCurrentlyMounted(baseDir.appendingPathComponent(candidateName).path) {
            candidateName = "\(preferredName) (\(suffix))"
            suffix += 1
        }
        return baseDir.appendingPathComponent(candidateName, isDirectory: true)
    }

    nonisolated private static func createConnectedSession(
        for connection: Connection,
        password: String
    ) async throws -> SFTPSessionProtocol {
        let session = await MainActor.run {
            DependencyContainer.shared.makeRemoteSession(for: connection.connectionType)
        }

        if connection.connectionType == .ftp {
            let streams = await MainActor.run {
                FTPTransferSettings.clamped(connection.ftpMaxStreams ?? FTPTransferSettings.shared.maxConcurrentStreams)
            }
            await session.setPreferredMaxStreams(streams)
        }

        if connection.connectionType == .sftp && connection.authMethod == .privateKey,
           let keyPath = connection.privateKeyPath {
            try await session.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                privateKeyPath: keyPath,
                passphrase: password.isEmpty ? nil : password,
                socksProxyPort: nil,
                socksProxyAllowLAN: false
            )
        } else {
            try await session.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password,
                socksProxyPort: nil,
                socksProxyAllowLAN: false
            )
        }
        return session
    }

    nonisolated private static func mountsBaseDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("macSSH/Mounts", isDirectory: true)
    }

    nonisolated private static func sanitizeVolumeName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\\0\r\n")
        let parts = name.components(separatedBy: invalid)
        let cleaned = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "macSSH Volume" : cleaned
    }

    nonisolated private static func runMountWebDAV(
        volumeName: String,
        webdavURL: String,
        mountPointPath: String
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/mount_webdav")
                process.arguments = [
                    "-S",
                    "-o", "browse",
                    "-v", volumeName,
                    webdavURL,
                    mountPointPath
                ]

                let errPipe = Pipe()
                process.standardOutput = FileHandle.nullDevice
                process.standardError = errPipe

                let finishLock = NSLock()
                var finished = false

                let completeOnce: (Result<Void, Error>) -> Void = { result in
                    finishLock.lock()
                    guard !finished else {
                        finishLock.unlock()
                        return
                    }
                    finished = true
                    finishLock.unlock()

                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                let timeoutItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                    completeOnce(.failure(AppError.connectionTimeout))
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15.0, execute: timeoutItem)

                process.terminationHandler = { proc in
                    timeoutItem.cancel()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if proc.terminationStatus == 0 {
                        completeOnce(.success(()))
                    } else {
                        let detail = errMsg.isEmpty ? "mount_webdav exited with code \(proc.terminationStatus)" : errMsg
                        completeOnce(.failure(AppError.connectionFailed(detail)))
                    }
                }

                do {
                    try process.run()
                } catch {
                    timeoutItem.cancel()
                    completeOnce(.failure(AppError.connectionFailed(error.localizedDescription)))
                }
            }
        }
    }

    nonisolated private static func unmountPathSync(_ path: String) {
        guard isPathCurrentlyMounted(path) else { return }

        let umount = Process()
        umount.executableURL = URL(fileURLWithPath: "/sbin/umount")
        umount.arguments = ["-f", path]
        umount.standardOutput = FileHandle.nullDevice
        umount.standardError = FileHandle.nullDevice
        try? umount.run()
        umount.waitUntilExit()

        if isPathCurrentlyMounted(path) {
            let diskutil = Process()
            diskutil.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            diskutil.arguments = ["unmount", "force", path]
            diskutil.standardOutput = FileHandle.nullDevice
            diskutil.standardError = FileHandle.nullDevice
            try? diskutil.run()
            diskutil.waitUntilExit()
        }
    }

    nonisolated private static func removeMountDirectoryIfEmptyOrSafe(_ url: URL) {
        guard !isPathCurrentlyMounted(url.path) else { return }
        Darwin.rmdir(url.path)
    }

    nonisolated private static func fetchMountedFileSystems() -> [Darwin.statfs] {
        var count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return [] }

        var stats = Array<Darwin.statfs>(repeating: Darwin.statfs(), count: Int(count) + 8)
        let bytes = Int32(stats.count * MemoryLayout<Darwin.statfs>.stride)
        count = stats.withUnsafeMutableBufferPointer { buf in
            getfsstat(buf.baseAddress, bytes, MNT_NOWAIT)
        }
        guard count > 0 else { return [] }
        return Array(stats.prefix(Int(count)))
    }

    nonisolated private static func stringFromCCharTuple<T>(_ tuple: T, maxLength: Int) -> String {
        withUnsafePointer(to: tuple) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxLength) { cstr in
                String(cString: cstr)
            }
        }
    }

    nonisolated private static func canonicalPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buf) != nil {
            return String(cString: buf)
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        if realpath(parent, &buf) != nil {
            return URL(fileURLWithPath: String(cString: buf))
                .appendingPathComponent(url.lastPathComponent)
                .path
        }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    nonisolated private static func isPathCurrentlyMounted(_ path: String) -> Bool {
        let normalizedTarget = URL(fileURLWithPath: path).standardizedFileURL.path
        let resolvedTarget = canonicalPath(path)

        for stat in fetchMountedFileSystems() {
            let mountedOn = stringFromCCharTuple(stat.f_mntonname, maxLength: Int(MAXPATHLEN))
            if mountedOn == normalizedTarget || mountedOn == resolvedTarget {
                return true
            }
        }
        return false
    }

    nonisolated private static func listCurrentWebDAVMounts(under basePath: String) -> [String] {
        let resolvedBase = canonicalPath(basePath)
        let rawPrefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        let resolvedPrefix = resolvedBase.hasSuffix("/") ? resolvedBase : resolvedBase + "/"
        var result: [String] = []
        for stat in fetchMountedFileSystems() {
            let fsType = stringFromCCharTuple(stat.f_fstypename, maxLength: Int(MFSTYPENAMELEN))
            let mountedOn = stringFromCCharTuple(stat.f_mntonname, maxLength: Int(MAXPATHLEN))
            if fsType == "webdav" && (mountedOn.hasPrefix(rawPrefix) || mountedOn.hasPrefix(resolvedPrefix)) {
                result.append(mountedOn)
            }
        }
        return result
    }

    nonisolated private static func registerEmergency(
        id: UUID,
        mountPath: String,
        server: WebDAVHTTPServer,
        bonjourHost: LocalBonjourHost?
    ) {
        emergencyLock.lock()
        emergencyMountPaths[id] = mountPath
        emergencyServers[id] = server
        if let bonjourHost {
            emergencyBonjourHosts[id] = bonjourHost
        }
        emergencyLock.unlock()
    }

    nonisolated private static func unregisterEmergency(id: UUID) {
        emergencyLock.lock()
        emergencyMountPaths.removeValue(forKey: id)
        emergencyServers.removeValue(forKey: id)
        emergencyBonjourHosts.removeValue(forKey: id)
        emergencyLock.unlock()
    }

    nonisolated private static func setupAtexitCleanup() {
        atexit {
            FinderMountManager.emergencyUnmountAllSync()
        }
    }
}
