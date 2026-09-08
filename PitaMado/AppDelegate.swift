import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let permissionManager = PermissionManager()
        if let outputIndex = CommandLine.arguments.firstIndex(of: "--check-accessibility-output"),
           CommandLine.arguments.indices.contains(outputIndex + 1) {
            let result = permissionManager.isAccessibilityTrusted ? "accessibility=trusted\n" : "accessibility=not-trusted\n"
            try? result.write(toFile: CommandLine.arguments[outputIndex + 1], atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
            return
        }

        if CommandLine.arguments.contains("--check-accessibility-and-quit") {
            print(permissionManager.isAccessibilityTrusted ? "accessibility=trusted" : "accessibility=not-trusted")
            NSApp.terminate(nil)
            return
        }

        let windowManager = WindowManager(permissionManager: permissionManager)
        if let outputIndex = CommandLine.arguments.firstIndex(of: "--tile-favorite-output"),
           CommandLine.arguments.indices.contains(outputIndex + 1) {
            let outputPath = CommandLine.arguments[outputIndex + 1]
            do {
                let count = try windowManager.tileFavoriteLayout()
                try? "favorite-layout=ok count=\(count)\n".write(toFile: outputPath, atomically: true, encoding: .utf8)
            } catch {
                try? "favorite-layout=error \(error.localizedDescription)\n".write(toFile: outputPath, atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
            return
        }

        menuBarController = MenuBarController(
            windowManager: windowManager,
            permissionManager: permissionManager
        )

        if !permissionManager.isAccessibilityTrusted {
            permissionManager.requestAccessibilityPermission()
            menuBarController?.showPermissionWarning()
        }
    }
}
