#if os(macOS)
import Foundation
import ServiceManagement

/// Provider-independent, OS-owned login registration. Development fixtures never register.
@MainActor
enum LoginItem {
    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Anti-Slop opens in the menu bar when you log in."
        case .requiresApproval: return "Allow Anti-Slop in macOS Login Items to finish enabling startup."
        case .notRegistered: return "Startup changes take effect when you choose Done."
        case .notFound: return "Open the built Anti-slop.app to enable startup."
        @unknown default: return "Check macOS Login Items for startup status."
        }
    }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func apply(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled && service.status != .requiresApproval { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
#endif
