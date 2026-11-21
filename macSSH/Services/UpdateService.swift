//
//  UpdateService.swift
//  macSSH
//
//  Lightweight native update checker against GitHub Releases.
//  Only checks official stable semver releases (e.g. 0.3.0), ignoring
//  pre-releases, drafts, alpha, beta, test, and demo builds.
//

import Foundation
import AppKit

// MARK: - Models & Strict Version Filter

nonisolated struct GitHubAssetDTO: Decodable, Sendable {
    let name: String
    let size: Int64
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case browserDownloadUrl = "browser_download_url"
    }
}

nonisolated struct GitHubReleaseDTO: Decodable, Sendable {
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlUrl: String
    let publishedAt: String?
    let assets: [GitHubAssetDTO]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case draft
        case prerelease
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

nonisolated struct ReleaseUpdateInfo: Identifiable, Equatable, Sendable {
    var id: String { version }
    let version: String
    let tagName: String
    let title: String
    let releaseNotes: String
    let publishedAt: Date?
    let htmlURL: URL
    let dmgDownloadURL: URL?
    let dmgFileName: String?
    let dmgSizeBytes: Int64
}

nonisolated enum ReleaseVersionFilter {
    private static let blockedTokens: Set<String> = [
        "alpha", "beta", "rc", "test", "testing",
        "demo", "preview", "dev", "nightly", "draft",
        "snapshot", "canary", "experimental"
    ]

    /// Parses a GitHub release ONLY if it represents an official stable version (e.g. `0.3.0` or `v0.3.0`).
    /// Rejects drafts, pre-releases, non-semver tags, or releases mentioning test/alpha/demo/beta keywords.
    static func parseStableRelease(_ dto: GitHubReleaseDTO) -> ReleaseUpdateInfo? {
        guard !dto.draft, !dto.prerelease else { return nil }

        let rawTag = dto.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTag.isEmpty else { return nil }

        let strippedTag: String
        if rawTag.hasPrefix("v") || rawTag.hasPrefix("V") {
            strippedTag = String(rawTag.dropFirst())
        } else {
            strippedTag = rawTag
        }

        // Strict numeric Major.Minor.Patch only (no `-alpha`, `-test`, `-demo`, letters, etc.)
        guard strippedTag.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
            return nil
        }

        if containsBlockedToken(rawTag) || containsBlockedToken(dto.name ?? "") {
            return nil
        }

        guard let htmlURL = URL(string: dto.htmlUrl) else { return nil }

        let dmgAsset = dto.assets.first { asset in
            let lower = asset.name.lowercased()
            return lower.hasSuffix(".dmg") && !containsBlockedToken(asset.name)
        } ?? dto.assets.first {
            $0.name.lowercased().hasSuffix(".dmg")
        }

        let publishedDate: Date? = dto.publishedAt.flatMap { raw in
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }

        return ReleaseUpdateInfo(
            version: strippedTag,
            tagName: rawTag,
            title: (dto.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? dto.name!.trimmingCharacters(in: .whitespacesAndNewlines)
                : strippedTag,
            releaseNotes: dto.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            publishedAt: publishedDate,
            htmlURL: htmlURL,
            dmgDownloadURL: dmgAsset.flatMap { URL(string: $0.browserDownloadUrl) },
            dmgFileName: dmgAsset?.name,
            dmgSizeBytes: dmgAsset?.size ?? 0
        )
    }

    static func containsBlockedToken(_ text: String) -> Bool {
        let tokens = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return tokens.contains { !$0.isEmpty && blockedTokens.contains($0) }
    }

    static func numericComponents(of version: String) -> [Int] {
        var cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        let core = cleaned.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? cleaned
        return core.split(separator: ".").compactMap { Int($0) }
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = numericComponents(of: lhs)
        let b = numericComponents(of: rhs)
        guard !a.isEmpty, !b.isEmpty else { return .orderedSame }

        let count = max(a.count, b.count)
        for i in 0..<count {
            let va = i < a.count ? a[i] : 0
            let vb = i < b.count ? b[i] : 0
            if va < vb { return .orderedAscending }
            if va > vb { return .orderedDescending }
        }
        return .orderedSame
    }

    static func selectLatestEligibleUpdate(
        from releases: [GitHubReleaseDTO],
        currentVersion: String
    ) -> ReleaseUpdateInfo? {
        let candidates = releases.compactMap { parseStableRelease($0) }
        guard let highest = candidates.max(by: { compareVersions($0.version, $1.version) == .orderedAscending }) else {
            return nil
        }
        guard compareVersions(highest.version, currentVersion) == .orderedDescending else {
            return nil
        }
        return highest
    }
}

// MARK: - DMG Download Delegate

private nonisolated final class DMGDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationFileName: String
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(destinationFileName: String, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destinationFileName = destinationFileName
        self.onProgress = onProgress
    }

    func setContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    private func resumeOnce(with result: Result<URL, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let targetURL = Self.allocateUniqueFileURL(in: downloadsDir, preferredName: destinationFileName)
            try FileManager.default.moveItem(at: location, to: targetURL)
            onProgress(1.0)
            resumeOnce(with: .success(targetURL))
        } catch {
            resumeOnce(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            resumeOnce(with: .failure(error))
        }
    }

    private static func allocateUniqueFileURL(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let initial = directory.appendingPathComponent(preferredName)
        if !fileManager.fileExists(atPath: initial.path) {
            return initial
        }

        let base = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension
        for index in 2...99 {
            let candidateName = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)-\(preferredName)")
    }
}

// MARK: - UpdateService

@MainActor
@Observable
final class UpdateService {
    static let shared = UpdateService()

    static let autoCheckUpdatesKey = "autoCheckUpdates"
    static let skippedUpdateVersionKey = "skippedUpdateVersion"
    private static let releasesAPIURL = URL(string: "https://api.github.com/repos/devduong/macSSH/releases?per_page=25")!

    private(set) var isChecking = false
    private(set) var isDownloading = false
    private(set) var isInstalling = false
    private(set) var isPerformingUpdateRestart = false
    private(set) var downloadProgress: Double = 0
    private(set) var availableUpdate: ReleaseUpdateInfo?
    private(set) var statusMessage: String?
    private(set) var isStatusError = false

    private(set) var skippedVersion: String? {
        didSet {
            if let skippedVersion, !skippedVersion.isEmpty {
                UserDefaults.standard.set(skippedVersion, forKey: Self.skippedUpdateVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.skippedUpdateVersionKey)
            }
        }
    }

    var isAutoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoCheckUpdatesKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.autoCheckUpdatesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoCheckUpdatesKey)
        }
    }

    @ObservationIgnored private var pendingLaunchCheck = false
    @ObservationIgnored private var unlockObserver: NSObjectProtocol?
    @ObservationIgnored private var downloadSession: URLSession?
    @ObservationIgnored private var downloadTask: URLSessionDownloadTask?

    private init() {
        self.skippedVersion = UserDefaults.standard.string(forKey: Self.skippedUpdateVersionKey)
        setupUnlockObserver()
    }

    // MARK: - Public Entry Points

    /// Runs automatic update check on launch if unlocked;
    /// otherwise waits until Touch ID / app lock is unlocked.
    func runLaunchCheckIfNeeded() async {
        if AppLockManager.shared.isLocked {
            pendingLaunchCheck = true
            return
        }

        // Brief delay so the main window finishes rendering before network I/O & optional prompt
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !AppLockManager.shared.isLocked else {
            pendingLaunchCheck = true
            return
        }

        pendingLaunchCheck = false
        await checkForUpdates(manual: false)
    }

    func checkForUpdates(manual: Bool) async {
        guard !isChecking else {
            if manual, availableUpdate != nil {
                UpdatePromptWindowController.shared.show()
            }
            return
        }

        isChecking = true
        statusMessage = L10n.tr("checking_for_updates")
        isStatusError = false
        defer { isChecking = false }

        do {
            let releases = try await fetchReleases()
            let currentVersion = AppVersion.version
            let latestUpdate = ReleaseVersionFilter.selectLatestEligibleUpdate(
                from: releases,
                currentVersion: currentVersion
            )

            guard let latest = latestUpdate else {
                availableUpdate = nil
                statusMessage = L10n.tr("up_to_date_message", currentVersion)
                isStatusError = false
                if manual {
                    presentUpToDateAlert(currentVersion: currentVersion)
                }
                return
            }

            // Always populate availableUpdate so the toolbar green-dot indicator and Help menu stay active
            availableUpdate = latest
            statusMessage = L10n.tr("update_version_summary", latest.version, currentVersion)
            isStatusError = false
            logInfo("[Update] Found new stable release v\(latest.version) (current: v\(currentVersion)).", category: .app)

            if !manual {
                guard isAutoCheckEnabled else {
                    logDebug("[Update] Automatic popup skipped (disabled by user); toolbar update indicator remains active.", category: .app)
                    return
                }
                // If user skipped this version (or a newer one), stay silent on automatic popup
                // until a version strictly greater than `skippedVersion` is released.
                if let skipped = skippedVersion,
                   ReleaseVersionFilter.compareVersions(latest.version, skipped) != .orderedDescending {
                    logInfo("[Update] Release v\(latest.version) popup skipped automatically (user skipped v\(skipped)).", category: .app)
                    return
                }
            }

            UpdatePromptWindowController.shared.show()
        } catch {
            logWarning("[Update] Failed to check updates: \(error.localizedDescription)", category: .network)
            statusMessage = "\(L10n.tr("update_check_failed")): \(error.localizedDescription)"
            isStatusError = true
            if manual {
                ToastManager.shared.show(
                    title: L10n.tr("update_check_failed"),
                    message: error.localizedDescription,
                    type: .error,
                    duration: 4.5
                )
            }
        }
    }

    func showAvailableUpdatePrompt() {
        guard availableUpdate != nil else { return }
        UpdatePromptWindowController.shared.show()
    }

    // MARK: - User Actions from Popup

    func skipCurrentUpdate() {
        if let version = availableUpdate?.version {
            skippedVersion = version
            logInfo("[Update] User skipped version v\(version); will remind on next version after v\(version).", category: .app)
        }
        cancelDownload()
        UpdatePromptWindowController.shared.close()
    }

    func neverRemindAgain() {
        isAutoCheckEnabled = false
        logInfo("[Update] User selected 'Never Remind Again'; automatic update checks disabled.", category: .app)
        cancelDownload()
        UpdatePromptWindowController.shared.close()
    }

    func remindMeLater() {
        cancelDownload()
        UpdatePromptWindowController.shared.close()
    }

    func resetSkippedVersion() {
        skippedVersion = nil
    }

    func downloadAndOpenUpdate() async {
        guard let release = availableUpdate else { return }
        guard let downloadURL = release.dmgDownloadURL else {
            NSWorkspace.shared.open(release.htmlURL)
            UpdatePromptWindowController.shared.close()
            return
        }
        guard !isDownloading, !isInstalling else { return }

        isDownloading = true
        isInstalling = false
        downloadProgress = 0

        let fileName = release.dmgFileName ?? "macSSH_\(release.version).dmg"
        let delegate = DMGDownloadDelegate(destinationFileName: fileName) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.downloadProgress = progress
            }
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.downloadSession = session

        do {
            let localFileURL: URL = try await withCheckedThrowingContinuation { continuation in
                delegate.setContinuation(continuation)
                let task = session.downloadTask(with: downloadURL)
                self.downloadTask = task
                task.resume()
            }

            isDownloading = false
            downloadTask = nil
            downloadSession?.finishTasksAndInvalidate()
            downloadSession = nil

            logSuccess("[Update] Downloaded \(localFileURL.lastPathComponent) — starting automatic install & reopen...", category: .app)
            isInstalling = true

            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try Self.stageAppFromDMG(dmgURL: localFileURL)
                }.value

                try await performSelfReplaceAndReopen(
                    stagedAppURL: staged.stagedAppURL,
                    stagingDir: staged.stagingDir,
                    downloadedDMGURL: localFileURL
                )
            } catch {
                isInstalling = false
                logWarning("[Update] Automatic install failed (\(error.localizedDescription)); falling back to opening DMG.", category: .app)
                ToastManager.shared.show(
                    title: L10n.tr("update_dmg_ready_title"),
                    message: L10n.tr("update_dmg_ready_msg", localFileURL.lastPathComponent),
                    type: .success,
                    duration: 6.0
                )
                NSWorkspace.shared.open(localFileURL)
                UpdatePromptWindowController.shared.close()
            }
        } catch {
            let isCancelled = (error as NSError).code == NSURLErrorCancelled
            isDownloading = false
            isInstalling = false
            downloadProgress = 0
            downloadTask = nil
            downloadSession?.invalidateAndCancel()
            downloadSession = nil

            if !isCancelled {
                logError("[Update] Download failed: \(error.localizedDescription)", category: .network)
                ToastManager.shared.show(
                    title: L10n.tr("update_download_failed"),
                    message: error.localizedDescription,
                    type: .error,
                    duration: 5.0
                )
            }
        }
    }

    func cancelDownload() {
        guard !isInstalling else { return }
        downloadTask?.cancel()
        downloadTask = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        isDownloading = false
        downloadProgress = 0
    }

    // MARK: - Self-Update & Reopen Engine

    nonisolated private static func stageAppFromDMG(dmgURL: URL) throws -> (stagingDir: URL, stagedAppURL: URL) {
        let fm = FileManager.default
        let uid = UUID().uuidString
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("macSSH_UpdateMount_\(uid)", isDirectory: true)
        let stagingDir = fm.temporaryDirectory.appendingPathComponent("macSSH_UpdateStage_\(uid)", isDirectory: true)

        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        var didMount = false
        defer {
            if didMount {
                _ = try? runProcess(
                    executable: "/usr/bin/hdiutil",
                    arguments: ["detach", mountPoint.path, "-force", "-quiet"]
                )
            }
            try? fm.removeItem(at: mountPoint)
        }

        // Attach DMG silently without opening Finder windows
        do {
            _ = try runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: [
                    "attach", dmgURL.path,
                    "-mountpoint", mountPoint.path,
                    "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-quiet"
                ]
            )
            didMount = true
        } catch {
            _ = try runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: [
                    "attach", dmgURL.path,
                    "-mountpoint", mountPoint.path,
                    "-nobrowse", "-readonly", "-noautoopen", "-quiet"
                ]
            )
            didMount = true
        }

        // Locate the .app bundle inside the mounted DMG volume
        let directCandidate = mountPoint.appendingPathComponent("macSSH.app", isDirectory: true)
        let appInDMG: URL
        if fm.fileExists(atPath: directCandidate.path) {
            appInDMG = directCandidate
        } else {
            let contents = try fm.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            guard let foundApp = contents.first(where: { $0.pathExtension.lowercased() == "app" }) else {
                throw AppError.connectionFailed("No .app bundle found inside downloaded DMG.")
            }
            appInDMG = foundApp
        }

        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedAppURL = stagingDir.appendingPathComponent(appInDMG.lastPathComponent, isDirectory: true)

        // Copy .app bundle preserving symlinks, permissions, and code signature
        do {
            _ = try runProcess(
                executable: "/usr/bin/ditto",
                arguments: [appInDMG.path, stagedAppURL.path]
            )
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw error
        }

        // Strip quarantine attributes so macOS Gatekeeper does not block relaunch
        _ = try? runProcess(
            executable: "/usr/bin/xattr",
            arguments: ["-cr", stagedAppURL.path]
        )

        return (stagingDir, stagedAppURL)
    }

    nonisolated private static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw AppError.connectionFailed(errStr.isEmpty ? "\(executable) exited with status \(process.terminationStatus)" : errStr)
        }
        return outStr
    }

    private func performSelfReplaceAndReopen(
        stagedAppURL: URL,
        stagingDir: URL,
        downloadedDMGURL: URL
    ) async throws {
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL
        let targetAppURL: URL
        if currentBundleURL.pathExtension.lowercased() == "app" && !currentBundleURL.path.hasPrefix("/Volumes/") {
            targetAppURL = currentBundleURL
        } else {
            targetAppURL = URL(fileURLWithPath: "/Applications/macSSH.app")
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macssh_update_installer_\(UUID().uuidString).sh")

        let scriptContent = """
        #!/bin/sh
        OLD_PID="$1"
        STAGED_APP="$2"
        TARGET_APP="$3"
        STAGING_DIR="$4"
        DMG_FILE="$5"
        SCRIPT_SELF="$0"

        # 1. Wait for the old macSSH instance to exit cleanly (up to 15s)
        i=0
        while kill -0 "$OLD_PID" 2>/dev/null; do
            sleep 0.1
            i=$((i + 1))
            if [ "$i" -ge 150 ]; then
                kill -9 "$OLD_PID" 2>/dev/null || true
                break
            fi
        done

        sleep 0.2

        # 2. Replace old .app bundle with staged .app bundle
        rm -rf "$TARGET_APP" 2>/dev/null
        if mv "$STAGED_APP" "$TARGET_APP" 2>/dev/null || /usr/bin/ditto "$STAGED_APP" "$TARGET_APP" 2>/dev/null; then
            /usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true
        else
            /usr/bin/osascript -e "do shell script \\"rm -rf '$TARGET_APP' && /usr/bin/ditto '$STAGED_APP' '$TARGET_APP' && /usr/bin/xattr -cr '$TARGET_APP'\\" with administrator privileges" >/dev/null 2>&1 || true
        fi

        # 3. Clean up staging directory and downloaded DMG
        rm -rf "$STAGING_DIR" 2>/dev/null || true
        rm -f "$DMG_FILE" 2>/dev/null || true

        # 4. Reopen the updated macSSH app
        /usr/bin/open "$TARGET_APP" || /usr/bin/open -n "$TARGET_APP"

        rm -f "$SCRIPT_SELF" 2>/dev/null || true
        """

        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Mark update restart in progress so applicationShouldTerminate exits without blocking prompt
        isPerformingUpdateRestart = true

        // Auto-save configuration if an active configuration file exists
        let configService = ConfigurationService.shared
        if configService.hasUnsavedChanges && configService.currentFileURL != nil {
            try? await configService.save()
        }

        // Perform full session/mount/process teardown BEFORE spawning the detached updater script
        TerminalLauncherService.cleanupOldScripts()
        await FinderMountManager.shared.unmountAll()
        await ConnectionSessionManager.shared.disconnectAll()
        NativeProcessRegistry.shared.terminateAll()

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            "/usr/bin/nohup /bin/sh \"$1\" \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" >/dev/null 2>&1 &",
            "sh",
            scriptURL.path,
            "\(currentPID)",
            stagedAppURL.path,
            targetAppURL.path,
            stagingDir.path,
            downloadedDMGURL.path
        ]
        launcher.standardInput = FileHandle.nullDevice
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        launcher.waitUntilExit()

        logInfo("[Update] Detached installer launched for target \(targetAppURL.path); terminating old instance (PID \(currentPID))...", category: .app)
        UpdatePromptWindowController.shared.close()

        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Darwin.exit(0)
        }
    }

    // MARK: - Private Helpers

    private func setupUnlockObserver() {
        unlockObserver = NotificationCenter.default.addObserver(
            forName: .appDidUnlock,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.pendingLaunchCheck else { return }
                self.pendingLaunchCheck = false
                await self.runLaunchCheckIfNeeded()
            }
        }
    }

    private func fetchReleases() async throws -> [GitHubReleaseDTO] {
        var request = URLRequest(url: Self.releasesAPIURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("macSSH/\(AppVersion.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.connectionFailed("Invalid server response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw AppError.connectionFailed("GitHub API returned HTTP \(http.statusCode)")
        }

        return try JSONDecoder().decode([GitHubReleaseDTO].self, from: data)
    }

    private func presentUpToDateAlert(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("up_to_date_title")
        alert.informativeText = L10n.tr("up_to_date_message", currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("ok"))
        alert.runModal()
    }
}
