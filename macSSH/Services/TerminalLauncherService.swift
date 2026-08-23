//
//  TerminalLauncherService.swift
//  macSSH
//
//  Launches native macOS Terminal.app connected to SSH servers
//

import Foundation
import AppKit

enum TerminalLauncherService {
    /// Dedicated directory for storing temporary .command scripts
    private static var scriptsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("macSSH_Terminal_Scripts", isDirectory: true)
    }

    /// Cleans up any leftover .command files from previous sessions or sudden terminations
    static func cleanupOldScripts() {
        let dir = scriptsDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            logInfo("Cleaned up \(files.count) temporary terminal script(s)", category: .app)
        } catch {
            logError("Failed to clean up temporary terminal scripts: \(error)", category: .app)
        }
    }

    /// Opens the specified SSH connection in native macOS Terminal.app
    static func openInMacOSTerminal(host: String, port: Int, username: String, privateKeyPath: String? = nil) {
        var sshCmd = "ssh -o StrictHostKeyChecking=no -p \(port)"
        if let keyPath = privateKeyPath, !keyPath.isEmpty {
            sshCmd += " -i '\(keyPath)'"
        }
        sshCmd += " \(username)@\(host)"

        do {
            let dir = scriptsDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let uniqueId = UUID().uuidString.prefix(8)
            let scriptURL = dir.appendingPathComponent("macSSH_ssh_\(uniqueId).command")

            let scriptContent = """
            #!/bin/bash
            clear
            echo "======================================================"
            echo "  macSSH - Connecting to \(username)@\(host):\(port)"
            echo "======================================================"
            echo ""
            \(sshCmd)
            """

            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            // Open using NSWorkspace
            let opened = NSWorkspace.shared.open(scriptURL)
            if !opened {
                // Fallback: spawn /usr/bin/open -a Terminal
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Terminal", scriptURL.path]
                try? process.run()
            }

            logInfo("Launched macOS Terminal with command: \(sshCmd)", category: .app)

            // Clean up this specific temporary script file after 60 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
                try? FileManager.default.removeItem(at: scriptURL)
            }
        } catch {
            logError("Failed to launch macOS Terminal: \(error)", category: .app)
        }
    }

    /// Opens from Connection domain model
    static func openInMacOSTerminal(connection: Connection) {
        openInMacOSTerminal(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            privateKeyPath: connection.privateKeyPath
        )
    }

    /// Opens from TerminalWindowData
    static func openInMacOSTerminal(windowData: TerminalWindowData) {
        openInMacOSTerminal(
            host: windowData.host,
            port: windowData.port,
            username: windowData.username,
            privateKeyPath: windowData.privateKeyPath
        )
    }
}
