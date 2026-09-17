import Foundation
import ServiceManagement

/// Registers the app to launch at login.
///
/// Uses the modern `SMAppService` API, which shows the app under
/// System Settings → General → Login Items. If that fails (for example when
/// running an unsigned development build from an unusual location), falls
/// back to a per-user LaunchAgent plist in `~/Library/LaunchAgents`.
enum LoginItemManager {
    private static let agentLabel = "com.clipstash.app.launcher"

    private static var agentPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)

        var isEnabled: Bool { self == .enabled }

        var description: String {
            switch self {
            case .enabled: return "Enabled"
            case .disabled: return "Disabled"
            case .requiresApproval: return "Waiting for approval in System Settings → Login Items"
            case .unavailable(let reason): return "Unavailable: \(reason)"
            }
        }
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound, .notRegistered:
            return FileManager.default.fileExists(atPath: agentPlistURL.path) ? .enabled : .disabled
        @unknown default:
            return .disabled
        }
    }

    static var isEnabled: Bool { status.isEnabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
                try? FileManager.default.removeItem(at: agentPlistURL)
            } catch {
                try writeLaunchAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            try? FileManager.default.removeItem(at: agentPlistURL)
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - LaunchAgent fallback

    private static func writeLaunchAgent() throws {
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: agentPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: agentPlistURL, options: .atomic)
    }
}
