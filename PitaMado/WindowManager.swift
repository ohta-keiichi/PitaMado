import AppKit
import ApplicationServices

enum WindowAction {
    case leftHalf
    case rightHalf
    case maximize
    case center
}

enum WindowManagerError: LocalizedError {
    case accessibilityPermissionMissing
    case activeWindowNotFound
    case visibleWindowsNotFound
    case screenNotFound
    case axOperationFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "アクセシビリティ権限がありません。システム設定でPitaMadoを許可してください。"
        case .activeWindowNotFound:
            return "操作対象の前面ウインドウを取得できませんでした。ChromeやFinderなどの通常ウインドウを前面にしてから再実行してください。"
        case .visibleWindowsNotFound:
            return "整列できる表示中ウインドウを取得できませんでした。通常のアプリウインドウを開いてから再実行してください。"
        case .screenNotFound:
            return "対象ウインドウがある画面を取得できませんでした。"
        case let .axOperationFailed(operation, error):
            return "\(operation) に失敗しました: \(error)"
        }
    }
}

private struct ManagedWindow {
    let element: AXUIElement
    let processID: pid_t
    let bundleIdentifier: String?
    let appName: String?
}

final class WindowManager {
    private let permissionManager: PermissionManager
    private let minimumWindowSize = CGSize(width: 80, height: 80)
    private let terminalBundleIdentifierCandidates = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "co.zeit.hyper",
        "com.github.wez.wezterm"
    ]
    private lazy var terminalBundleIdentifiers = Set(terminalBundleIdentifierCandidates)
    private let chromeBundleIdentifierCandidates = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser"
    ]
    private lazy var chromeBundleIdentifiers = Set(chromeBundleIdentifierCandidates)
    private let visualStudioCodeBundleIdentifier = "com.microsoft.VSCode"
    private let finderBundleIdentifier = "com.apple.finder"
    private let favoriteChromeWindowCount = 1
    private let favoriteFinderWindowCount = 2
    private let favoriteTerminalWindowCount = 2

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    func apply(_ action: WindowAction) throws {
        guard permissionManager.isAccessibilityTrusted else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        let window = try frontmostWindow()
        let currentFrame = readFrame(of: window)
        let screen = screen(containingAXFrame: currentFrame) ?? NSScreen.main

        guard let screen else {
            throw WindowManagerError.screenNotFound
        }

        let targetFrame = targetFrame(for: action, on: screen)
        try setFrame(targetFrame, for: window)
    }

    @discardableResult
    func tileAllVisibleWindows() throws -> Int {
        guard permissionManager.isAccessibilityTrusted else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        guard let screen = NSScreen.main else {
            throw WindowManagerError.screenNotFound
        }

        let windows = visibleWindows(on: screen).map(\.element)
        guard !windows.isEmpty else {
            throw WindowManagerError.visibleWindowsNotFound
        }

        let frames = tileFrames(forCount: windows.count, on: screen)
        for (window, frame) in zip(windows, frames) {
            do {
                try setFrame(frame, for: window)
            } catch {
                NSLog("PitaMado: 整列スキップ: %@", error.localizedDescription)
            }
        }

        return windows.count
    }

    @discardableResult
    func tileTerminalsBottomOthersTop() throws -> Int {
        guard permissionManager.isAccessibilityTrusted else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        guard let screen = NSScreen.main else {
            throw WindowManagerError.screenNotFound
        }

        let windows = visibleWindows(on: screen)
        guard !windows.isEmpty else {
            throw WindowManagerError.visibleWindowsNotFound
        }

        let terminals = windows.filter(isTerminalWindow)
        let others = windows.filter { !isTerminalWindow($0) }

        if terminals.isEmpty || others.isEmpty {
            let frames = tileFrames(forCount: windows.count, in: axFrame(fromCocoaFrame: screen.visibleFrame))
            for (window, frame) in zip(windows, frames) {
                try? setFrame(frame, for: window.element)
            }
            return windows.count
        }

        let visibleFrame = axFrame(fromCocoaFrame: screen.visibleFrame)
        let topFrame = CGRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y,
            width: visibleFrame.width,
            height: (visibleFrame.height / 2).rounded(.down)
        )
        let bottomFrame = CGRect(
            x: visibleFrame.origin.x,
            y: topFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.maxY - topFrame.maxY
        )

        let topFrames = horizontalFrames(forCount: others.count, in: topFrame)
        let bottomFrames = horizontalFrames(forCount: terminals.count, in: bottomFrame)

        for (window, frame) in zip(others, topFrames) {
            try? setFrame(frame, for: window.element)
        }

        for (window, frame) in zip(terminals, bottomFrames) {
            try? setFrame(frame, for: window.element)
        }

        return windows.count
    }

    @discardableResult
    func tileFavoriteLayout() throws -> Int {
        guard permissionManager.isAccessibilityTrusted else {
            throw WindowManagerError.accessibilityPermissionMissing
        }

        guard let screen = NSScreen.main else {
            throw WindowManagerError.screenNotFound
        }

        let windows = visibleWindows(on: screen)
        guard !windows.isEmpty else {
            throw WindowManagerError.visibleWindowsNotFound
        }

        let chromeWindows = Array(windows.filter(isChromeWindow).prefix(favoriteChromeWindowCount))
        let visualStudioCodeWindows = chromeWindows.isEmpty
            ? Array(windows.filter(isVisualStudioCodeWindow).prefix(favoriteChromeWindowCount))
            : []
        let finderWindows = Array(windows.filter(isFinderWindow).prefix(favoriteFinderWindowCount))
        let terminalWindows = Array(windows.filter(isTerminalWindow).prefix(favoriteTerminalWindowCount))
        let arrangedWindowKeys = Set((chromeWindows + visualStudioCodeWindows + finderWindows + terminalWindows).map { windowKey(for: $0.element) })

        guard !arrangedWindowKeys.isEmpty else {
            throw WindowManagerError.visibleWindowsNotFound
        }

        let visibleFrame = axFrame(fromCocoaFrame: screen.visibleFrame)
        let leftFrame = CGRect(
            x: visibleFrame.origin.x,
            y: visibleFrame.origin.y,
            width: (visibleFrame.width / 3).rounded(.down),
            height: visibleFrame.height
        )
        let rightFrame = CGRect(
            x: leftFrame.maxX,
            y: visibleFrame.origin.y,
            width: visibleFrame.maxX - leftFrame.maxX,
            height: visibleFrame.height
        )
        let finderFrame = CGRect(
            x: rightFrame.origin.x,
            y: rightFrame.origin.y,
            width: rightFrame.width,
            height: (rightFrame.height / 2).rounded(.down)
        )
        let terminalFrame = CGRect(
            x: rightFrame.origin.x,
            y: finderFrame.maxY,
            width: rightFrame.width,
            height: rightFrame.maxY - finderFrame.maxY
        )

        tileFixed(chromeWindows, in: [leftFrame])
        tileFixed(visualStudioCodeWindows, in: [leftFrame])
        // Finder uses 20% and 46% of the full screen width (the right two-thirds).
        tileFixed(finderWindows, in: splitFrame(finderFrame, widthRatios: [0.20, 0.46]))
        tileFixed(terminalWindows, in: splitFrame(terminalFrame, widthRatios: [0.5, 0.5]))

        return arrangedWindowKeys.count
    }

    private func frontmostWindow() throws -> AXUIElement {
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           let window = focusedWindow(forProcessID: frontApp.processIdentifier) {
            return window
        }

        if let pid = topVisibleWindowProcessID(excluding: ProcessInfo.processInfo.processIdentifier),
           let window = focusedWindow(forProcessID: pid) {
            return window
        }

        throw WindowManagerError.activeWindowNotFound
    }

    private func focusedWindow(forProcessID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)

        if let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute, from: app) {
            return focusedWindow
        }

        if let mainWindow = copyElementAttribute(kAXMainWindowAttribute, from: app) {
            return mainWindow
        }

        if let windows = copyArrayAttribute(kAXWindowsAttribute, from: app), !windows.isEmpty {
            return windows[0]
        }

        return nil
    }

    private func topVisibleWindowProcessID(excluding ownPID: pid_t) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfoList {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let width = bounds["Width"] as? CGFloat,
                let height = bounds["Height"] as? CGFloat,
                width > minimumWindowSize.width,
                height > minimumWindowSize.height
            else {
                continue
            }

            return pid
        }

        return nil
    }

    private func visibleWindows(on screen: NSScreen) -> [ManagedWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let targetScreenFrame = axFrame(fromCocoaFrame: screen.visibleFrame)
        var result: [ManagedWindow] = []
        var usedWindowKeys = Set<String>()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        for info in windowInfoList {
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                pid != ownPID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                let bounds = info[kCGWindowBounds as String] as? [String: Any],
                let cgFrame = cgFrame(fromWindowBounds: bounds),
                cgFrame.width > minimumWindowSize.width,
                cgFrame.height > minimumWindowSize.height,
                cgFrame.intersects(targetScreenFrame),
                let axWindow = matchingAXWindow(forProcessID: pid, cgFrame: cgFrame)
            else {
                continue
            }

            let key = windowKey(for: axWindow)
            guard !usedWindowKeys.contains(key) else {
                continue
            }

            usedWindowKeys.insert(key)
            let app = NSRunningApplication(processIdentifier: pid)
            result.append(
                ManagedWindow(
                    element: axWindow,
                    processID: pid,
                    bundleIdentifier: app?.bundleIdentifier,
                    appName: app?.localizedName
                )
            )
        }

        return result
    }

    private func isTerminalWindow(_ window: ManagedWindow) -> Bool {
        if let bundleIdentifier = window.bundleIdentifier,
           terminalBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard let appName = window.appName?.lowercased() else {
            return false
        }

        return appName.contains("terminal")
            || appName.contains("iterm")
            || appName.contains("warp")
            || appName.contains("ghostty")
            || appName.contains("wezterm")
            || appName.contains("hyper")
    }

    private func isChromeWindow(_ window: ManagedWindow) -> Bool {
        if let bundleIdentifier = window.bundleIdentifier,
           chromeBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        guard let appName = window.appName?.lowercased() else {
            return false
        }

        return appName.contains("chrome")
            || appName.contains("edge")
            || appName.contains("brave")
            || appName.contains("vivaldi")
            || appName == "arc"
    }

    private func isVisualStudioCodeWindow(_ window: ManagedWindow) -> Bool {
        if window.bundleIdentifier == visualStudioCodeBundleIdentifier {
            return true
        }

        return window.appName?.lowercased() == "visual studio code"
    }

    private func isFinderWindow(_ window: ManagedWindow) -> Bool {
        if window.bundleIdentifier == finderBundleIdentifier {
            return true
        }

        return window.appName?.lowercased() == "finder"
    }

    private func matchingAXWindow(forProcessID pid: pid_t, cgFrame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = copyArrayAttribute(kAXWindowsAttribute, from: app) else {
            return nil
        }

        return windows.first { window in
            guard let axFrame = readFrame(of: window) else {
                return false
            }

            return framesAreClose(axFrame, cgFrame)
        }
    }

    private func cgFrame(fromWindowBounds bounds: [String: Any]) -> CGRect? {
        guard
            let x = bounds["X"] as? CGFloat,
            let y = bounds["Y"] as? CGFloat,
            let width = bounds["Width"] as? CGFloat,
            let height = bounds["Height"] as? CGFloat
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func framesAreClose(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.origin.x - second.origin.x) <= 12
            && abs(first.origin.y - second.origin.y) <= 12
            && abs(first.width - second.width) <= 24
            && abs(first.height - second.height) <= 24
    }

    private func windowKey(for window: AXUIElement) -> String {
        if let frame = readFrame(of: window) {
            return "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height))"
        }

        return String(ObjectIdentifier(window as AnyObject).hashValue)
    }

    private func copyElementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard error == .success else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyArrayAttribute(_ attribute: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard error == .success else {
            return nil
        }

        return value as? [AXUIElement]
    }

    private func readFrame(of window: AXUIElement) -> CGRect? {
        guard
            let position = readCGPointAttribute(kAXPositionAttribute, from: window),
            let size = readCGSizeAttribute(kAXSizeAttribute, from: window)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func readCGPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard error == .success, let axValue = value else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue((axValue as! AXValue), .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func readCGSizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        guard error == .success, let axValue = value else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue((axValue as! AXValue), .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) throws {
        var size = frame.size
        var position = frame.origin

        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowManagerError.activeWindowNotFound
        }

        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
            throw WindowManagerError.activeWindowNotFound
        }

        let sizeError = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeError == .success else {
            throw WindowManagerError.axOperationFailed("サイズ変更", sizeError)
        }

        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        guard positionError == .success else {
            throw WindowManagerError.axOperationFailed("位置変更", positionError)
        }
    }

    private func targetFrame(for action: WindowAction, on screen: NSScreen) -> CGRect {
        let visibleFrame = axFrame(fromCocoaFrame: screen.visibleFrame)
        let roundedX = visibleFrame.origin.x.rounded(.down)
        let roundedY = visibleFrame.origin.y.rounded(.down)
        let roundedWidth = visibleFrame.width.rounded(.down)
        let roundedHeight = visibleFrame.height.rounded(.down)

        switch action {
        case .leftHalf:
            return CGRect(x: roundedX, y: roundedY, width: (roundedWidth / 2).rounded(.down), height: roundedHeight)
        case .rightHalf:
            let width = (roundedWidth / 2).rounded(.down)
            return CGRect(x: roundedX + width, y: roundedY, width: roundedWidth - width, height: roundedHeight)
        case .maximize:
            return CGRect(x: roundedX, y: roundedY, width: roundedWidth, height: roundedHeight)
        case .center:
            let width = (roundedWidth * 0.7).rounded(.down)
            let height = (roundedHeight * 0.7).rounded(.down)
            return CGRect(
                x: roundedX + ((roundedWidth - width) / 2).rounded(.down),
                y: roundedY + ((roundedHeight - height) / 2).rounded(.down),
                width: width,
                height: height
            )
        }
    }

    private func tileFrames(forCount count: Int, on screen: NSScreen) -> [CGRect] {
        tileFrames(forCount: count, in: axFrame(fromCocoaFrame: screen.visibleFrame))
    }

    private func tileFrames(forCount count: Int, in visibleFrame: CGRect) -> [CGRect] {
        let rows = count <= 1 ? 1 : 2
        let columns = Int(ceil(Double(count) / Double(rows)))
        let cellWidth = (visibleFrame.width / CGFloat(columns)).rounded(.down)
        let cellHeight = (visibleFrame.height / CGFloat(rows)).rounded(.down)

        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            let isLastColumn = column == columns - 1
            let isLastRow = row == rows - 1
            let x = visibleFrame.origin.x + CGFloat(column) * cellWidth
            let y = visibleFrame.origin.y + CGFloat(row) * cellHeight
            let width = isLastColumn ? visibleFrame.maxX - x : cellWidth
            let height = isLastRow ? visibleFrame.maxY - y : cellHeight

            return CGRect(
                x: x.rounded(.down),
                y: y.rounded(.down),
                width: width.rounded(.down),
                height: height.rounded(.down)
            )
        }
    }

    private func horizontalFrames(forCount count: Int, in frame: CGRect) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        let cellWidth = (frame.width / CGFloat(count)).rounded(.down)

        return (0..<count).map { index in
            let x = frame.origin.x + CGFloat(index) * cellWidth
            let width = index == count - 1 ? frame.maxX - x : cellWidth

            return CGRect(
                x: x.rounded(.down),
                y: frame.origin.y.rounded(.down),
                width: width.rounded(.down),
                height: frame.height.rounded(.down)
            )
        }
    }

    private func tile(_ windows: [ManagedWindow], in frame: CGRect) {
        let frames = tileFrames(forCount: windows.count, in: frame)

        for (window, frame) in zip(windows, frames) {
            do {
                try setFrame(frame, for: window.element)
            } catch {
                NSLog("PitaMado: 整列スキップ: %@", error.localizedDescription)
            }
        }
    }

    private func tileFixed(_ windows: [ManagedWindow], in frames: [CGRect]) {
        for (window, frame) in zip(windows, frames) {
            do {
                try setFrame(frame, for: window.element)
            } catch {
                NSLog("PitaMado: 整列スキップ: %@", error.localizedDescription)
            }
        }
    }

    private func splitFrame(_ frame: CGRect, widthRatios: [CGFloat]) -> [CGRect] {
        let totalRatio = widthRatios.reduce(0, +)
        guard totalRatio > 0 else {
            return []
        }

        var currentX = frame.origin.x
        return widthRatios.enumerated().map { index, ratio in
            let isLast = index == widthRatios.count - 1
            let width = isLast ? frame.maxX - currentX : (frame.width * ratio / totalRatio).rounded(.down)
            let result = CGRect(
                x: currentX.rounded(.down),
                y: frame.origin.y.rounded(.down),
                width: width.rounded(.down),
                height: frame.height.rounded(.down)
            )
            currentX += width
            return result
        }
    }

    private func screen(containingAXFrame frame: CGRect?) -> NSScreen? {
        guard let frame else {
            return NSScreen.main
        }

        let axCenter = CGPoint(x: frame.midX, y: frame.midY)
        let cocoaCenter = CGPoint(x: axCenter.x, y: globalTopY - axCenter.y)

        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }

    private func axFrame(fromCocoaFrame frame: CGRect) -> CGRect {
        CGRect(
            x: frame.origin.x,
            y: globalTopY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private var globalTopY: CGFloat {
        NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
    }
}
