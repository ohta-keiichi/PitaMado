import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let windowManager: WindowManager
    private let permissionManager: PermissionManager

    init(windowManager: WindowManager, permissionManager: PermissionManager) {
        self.windowManager = windowManager
        self.permissionManager = permissionManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        rebuildMenu()
    }

    func showPermissionWarning() {
        showAlert(
            title: "アクセシビリティ権限が必要です",
            message: "PitaMadoで他のアプリのウインドウを操作するには、システム設定でアクセシビリティ権限を許可してください。"
        )
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "PitaMadoMenuIcon", ofType: "svg") {
                button.image = NSImage(contentsOfFile: iconPath)
            } else {
                button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "PitaMado")
            }
            button.image?.isTemplate = true
            button.image?.size = NSSize(width: 18, height: 18)
            button.title = ""
            button.toolTip = "PitaMado"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let permissionTitle = permissionManager.isAccessibilityTrusted ? "アクセシビリティ権限: 許可済み" : "アクセシビリティ権限: 未許可"
        let permissionStatusItem = NSMenuItem(title: permissionTitle, action: nil, keyEquivalent: "")
        permissionStatusItem.isEnabled = false
        menu.addItem(permissionStatusItem)
        menu.addItem(.separator())

        menu.addItem(menuItem(title: "左半分", action: #selector(moveLeftHalf)))
        menu.addItem(menuItem(title: "右半分", action: #selector(moveRightHalf)))
        menu.addItem(menuItem(title: "最大化", action: #selector(maximize)))
        menu.addItem(menuItem(title: "中央配置", action: #selector(center)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "すべて整列", action: #selector(tileAllVisibleWindows)))
        menu.addItem(menuItem(title: "ターミナル下・他上", action: #selector(tileTerminalsBottom)))
        menu.addItem(menuItem(title: "お気に入り配置", action: #selector(tileFavoriteLayout)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "アクセシビリティ権限を開く", action: #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "終了", action: #selector(quit)))

        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func runWindowAction(_ action: WindowAction) {
        do {
            try windowManager.apply(action)
        } catch {
            NSLog("PitaMado: %@", error.localizedDescription)
            showAlert(title: "ウインドウを操作できませんでした", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func moveLeftHalf() {
        runWindowAction(.leftHalf)
    }

    @objc private func moveRightHalf() {
        runWindowAction(.rightHalf)
    }

    @objc private func maximize() {
        runWindowAction(.maximize)
    }

    @objc private func center() {
        runWindowAction(.center)
    }

    @objc private func tileAllVisibleWindows() {
        do {
            let count = try windowManager.tileAllVisibleWindows()
            NSLog("PitaMado: %d個のウインドウを整列しました", count)
        } catch {
            NSLog("PitaMado: %@", error.localizedDescription)
            showAlert(title: "ウインドウを整列できませんでした", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func tileTerminalsBottom() {
        do {
            let count = try windowManager.tileTerminalsBottomOthersTop()
            NSLog("PitaMado: %d個のウインドウを上下に分類して整列しました", count)
        } catch {
            NSLog("PitaMado: %@", error.localizedDescription)
            showAlert(title: "ウインドウを整列できませんでした", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func tileFavoriteLayout() {
        do {
            let count = try windowManager.tileFavoriteLayout()
            NSLog("PitaMado: %d個のウインドウをお気に入り配置に整列しました", count)
        } catch {
            NSLog("PitaMado: %@", error.localizedDescription)
            showAlert(title: "ウインドウを整列できませんでした", message: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
