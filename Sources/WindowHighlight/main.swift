import AppKit
import ApplicationServices

private enum DefaultsKey {
    static let enabled = "enabled"
    static let borderWidth = "borderWidth"
    static let colorRed = "colorRed"
    static let colorGreen = "colorGreen"
    static let colorBlue = "colorBlue"
    static let colorAlpha = "colorAlpha"
    static let borderEnabled = "borderEnabled"
    static let dimEnabled = "dimEnabled"
    static let dimAlpha = "dimAlpha"
    static let applyToAllDisplays = "applyToAllDisplays"
}

@MainActor
private final class Preferences {
    static let shared = Preferences()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.enabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.enabled) }
    }

    var borderWidth: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: DefaultsKey.borderWidth)
            return value > 0 ? CGFloat(value) : 4
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: DefaultsKey.borderWidth) }
    }

    var borderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.borderEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.borderEnabled) }
    }

    var borderColor: NSColor {
        get {
            let defaults = UserDefaults.standard
            let red = defaults.object(forKey: DefaultsKey.colorRed) as? Double ?? 1.0
            let green = defaults.object(forKey: DefaultsKey.colorGreen) as? Double ?? 0.0
            let blue = defaults.object(forKey: DefaultsKey.colorBlue) as? Double ?? 0.85
            let alpha = defaults.object(forKey: DefaultsKey.colorAlpha) as? Double ?? 0.95
            return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
        }
        set {
            guard let color = newValue.usingColorSpace(.deviceRGB) else { return }
            UserDefaults.standard.set(Double(color.redComponent), forKey: DefaultsKey.colorRed)
            UserDefaults.standard.set(Double(color.greenComponent), forKey: DefaultsKey.colorGreen)
            UserDefaults.standard.set(Double(color.blueComponent), forKey: DefaultsKey.colorBlue)
            UserDefaults.standard.set(Double(color.alphaComponent), forKey: DefaultsKey.colorAlpha)
        }
    }

    var dimEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.dimEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.dimEnabled) }
    }

    var dimAlpha: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: DefaultsKey.dimAlpha)
            return value > 0 ? CGFloat(value) : 0.18
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: DefaultsKey.dimAlpha) }
    }

    var applyToAllDisplays: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.applyToAllDisplays) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.applyToAllDisplays) }
    }
}

private struct ActiveWindowBounds {
    let frame: CGRect
    let applicationName: String
}

private struct OverlayRenderState: Equatable {
    let frame: CGRect
    let width: CGFloat
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
    let borderEnabled: Bool
    let dimEnabled: Bool
    let dimAlpha: Int
    let applyToAllDisplays: Bool

    init(frame: CGRect, color: NSColor, width: CGFloat, borderEnabled: Bool, dimEnabled: Bool, dimAlpha: CGFloat, applyToAllDisplays: Bool) {
        self.frame = CGRect(
            x: frame.minX.rounded(),
            y: frame.minY.rounded(),
            width: frame.width.rounded(),
            height: frame.height.rounded()
        )
        self.width = width.rounded()

        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        red = Int((rgb.redComponent * 255).rounded())
        green = Int((rgb.greenComponent * 255).rounded())
        blue = Int((rgb.blueComponent * 255).rounded())
        alpha = Int((rgb.alphaComponent * 255).rounded())
        self.borderEnabled = borderEnabled
        self.dimEnabled = dimEnabled
        self.dimAlpha = Int((dimAlpha * 255).rounded())
        self.applyToAllDisplays = applyToAllDisplays
    }
}

private final class AccessibilityWindowReader {
    func requestPermissionIfNeeded() {
        guard !isTrusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func activeWindowBounds() -> ActiveWindowBounds? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return nil
        }

        if let cgFrame = frontmostCGWindowFrame(for: application.processIdentifier),
           let frame = convertAccessibilityFrameToAppKit(cgFrame),
           frame.width > 40,
           frame.height > 40 {
            return ActiveWindowBounds(
                frame: frame,
                applicationName: application.localizedName ?? "Unknown"
            )
        }

        guard isTrusted else {
            return nil
        }

        let cgFrame = frameFromCoreGraphics(for: application)
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        var windowElement: AXUIElement?
        if focusedResult == .success, let focusedWindow {
            windowElement = (focusedWindow as! AXUIElement)
        } else {
            windowElement = firstWindow(in: appElement)
        }

        let axFrame = windowElement.flatMap { frame(of: $0) }.flatMap { convertAccessibilityFrameToAppKit($0) }

        guard let frame = cgFrame ?? axFrame,
              frame.width > 40,
              frame.height > 40
        else {
            return nil
        }

        return ActiveWindowBounds(frame: frame, applicationName: application.localizedName ?? "Unknown")
    }

    private func frontmostCGWindowFrame(for processIdentifier: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = numberValue(bounds["X"]),
                  let y = numberValue(bounds["Y"]),
                  let width = numberValue(bounds["Width"]),
                  let height = numberValue(bounds["Height"]),
                  width > 180,
                  height > 140
            else {
                continue
            }

            return CGRect(x: x, y: y, width: width, height: height)
        }

        return nil
    }

    private func numberValue(_ value: Any?) -> CGFloat? {
        switch value {
        case let value as CGFloat:
            return value
        case let value as Double:
            return CGFloat(value)
        case let value as Int:
            return CGFloat(value)
        case let value as NSNumber:
            return CGFloat(truncating: value)
        default:
            return nil
        }
    }

    private func firstWindow(in appElement: AXUIElement) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }
        return windows.first
    }

    private func frameFromCoreGraphics(for application: NSRunningApplication) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == application.processIdentifier,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]),
                  width > 40,
                  height > 40
            else {
                continue
            }

            return convertAccessibilityFrameToAppKit(CGRect(x: x, y: y, width: width, height: height))
        }

        return nil
    }

    private func number(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }

        if let value = value as? NSNumber {
            return CGFloat(value.doubleValue)
        }

        return nil
    }

    private func frame(of windowElement: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionValue,
              let sizeValue
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func convertAccessibilityFrameToAppKit(_ frame: CGRect) -> CGRect? {
        let displays = NSScreen.screens.compactMap { screen -> DisplayCoordinateSpace? in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            return DisplayCoordinateSpace(
                appKitFrame: screen.frame,
                coreGraphicsBounds: CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
            )
        }

        return CoordinateConverter.convertAccessibilityFrameToAppKit(
            frame,
            displays: displays,
            fallbackMainScreenFrame: NSScreen.main?.frame
        )
    }
}

private final class BorderStripWindow: NSWindow {
    private let stripView = NSView(frame: .zero)

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        stripView.wantsLayer = true
        stripView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = stripView
    }

    func setFillColor(_ color: NSColor) {
        stripView.layer?.backgroundColor = color.cgColor
    }
}

@MainActor
private final class OverlayController {
    private let top = BorderStripWindow()
    private let right = BorderStripWindow()
    private let bottom = BorderStripWindow()
    private let left = BorderStripWindow()

    private var windows: [BorderStripWindow] {
        [top, right, bottom, left]
    }
    private var dimWindows: [BorderStripWindow] = []

    func show(around frame: CGRect, color: NSColor, width: CGFloat, borderEnabled: Bool, dimEnabled: Bool, dimAlpha: CGFloat, applyToAllDisplays: Bool) {
        let targetScreens = targetScreens(applyToAllDisplays: applyToAllDisplays)

        showDimmer(around: frame, on: targetScreens, enabled: dimEnabled, alpha: dimAlpha)
        if borderEnabled, intersectsAnyTargetScreen(frame, targetScreens) {
            showBorder(around: frame, color: color, width: width)
        } else {
            hideBorder()
        }
    }

    private func showBorder(around frame: CGRect, color: NSColor, width: CGFloat) {
        let width = max(2, min(width, 24))
        let expanded = frame.insetBy(dx: -width, dy: -width)

        bottom.setFrame(
            CGRect(x: expanded.minX, y: expanded.minY, width: expanded.width, height: width),
            display: true
        )
        top.setFrame(
            CGRect(x: expanded.minX, y: frame.maxY, width: expanded.width, height: width),
            display: true
        )
        left.setFrame(
            CGRect(x: expanded.minX, y: frame.minY, width: width, height: frame.height),
            display: true
        )
        right.setFrame(
            CGRect(x: frame.maxX, y: frame.minY, width: width, height: frame.height),
            display: true
        )

        for window in windows {
            window.setFillColor(color)
            window.orderFrontRegardless()
        }
    }

    func hide() {
        hideBorder()
        hideDimmer()
    }

    private func hideBorder() {
        for window in windows {
            window.orderOut(nil)
        }
    }

    private func showDimmer(around activeFrame: CGRect, on screens: [NSScreen], enabled: Bool, alpha: CGFloat) {
        guard enabled, alpha > 0 else {
            hideDimmer()
            return
        }

        let rects = dimmingRects(around: activeFrame, on: screens)
        ensureDimWindows(count: rects.count)
        let color = NSColor.black.withAlphaComponent(max(0.04, min(alpha, 0.65)))

        for index in dimWindows.indices {
            guard index < rects.count else {
                dimWindows[index].orderOut(nil)
                continue
            }

            dimWindows[index].setFrame(rects[index], display: true)
            dimWindows[index].setFillColor(color)
            dimWindows[index].level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
            dimWindows[index].orderFrontRegardless()
        }
    }

    private func hideDimmer() {
        for window in dimWindows {
            window.orderOut(nil)
        }
    }

    private func ensureDimWindows(count: Int) {
        guard dimWindows.count < count else {
            return
        }

        for _ in dimWindows.count..<count {
            dimWindows.append(BorderStripWindow())
        }
    }

    private func dimmingRects(around activeFrame: CGRect, on screens: [NSScreen]) -> [CGRect] {
        var rects: [CGRect] = []

        for screen in screens {
            let screenFrame = screen.frame
            let active = screenFrame.intersection(activeFrame)

            if active.isNull || active.isEmpty {
                rects.append(screenFrame)
                continue
            }

            appendRect(&rects, CGRect(x: screenFrame.minX, y: active.maxY, width: screenFrame.width, height: screenFrame.maxY - active.maxY))
            appendRect(&rects, CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: active.minY - screenFrame.minY))
            appendRect(&rects, CGRect(x: screenFrame.minX, y: active.minY, width: active.minX - screenFrame.minX, height: active.height))
            appendRect(&rects, CGRect(x: active.maxX, y: active.minY, width: screenFrame.maxX - active.maxX, height: active.height))
        }

        return rects
    }

    private func targetScreens(applyToAllDisplays: Bool) -> [NSScreen] {
        if applyToAllDisplays {
            return NSScreen.screens
        }

        return NSScreen.main.map { [$0] } ?? NSScreen.screens.prefix(1).map { $0 }
    }

    private func intersectsAnyTargetScreen(_ frame: CGRect, _ screens: [NSScreen]) -> Bool {
        screens.contains { !$0.frame.intersection(frame).isNull && !$0.frame.intersection(frame).isEmpty }
    }

    private func appendRect(_ rects: inout [CGRect], _ rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        rects.append(rect)
    }
}

@MainActor
private final class PreferencesPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
private final class WheelAdjustingSlider: NSSlider {
    var onWheelStep: ((Double) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }

        onWheelStep?(delta > 0 ? 1 : -1)
    }
}

@MainActor
private final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let borderCheckbox = NSButton(checkboxWithTitle: "枠を表示", target: nil, action: nil)
    private let colorWell = NSColorWell(frame: .zero)
    private let widthSlider = WheelAdjustingSlider(value: 4, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let widthLabel = NSTextField(labelWithString: "")
    private let dimCheckbox = NSButton(checkboxWithTitle: "周囲を暗くする", target: nil, action: nil)
    private let dimSlider = WheelAdjustingSlider(value: 18, minValue: 4, maxValue: 65, target: nil, action: nil)
    private let dimLabel = NSTextField(labelWithString: "")
    private let allDisplaysCheckbox = NSButton(checkboxWithTitle: "すべてのモニターに適用", target: nil, action: nil)
    var onClose: (() -> Void)?

    init() {
        let window = PreferencesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 310),
            styleMask: [.titled, .closable, .miniaturizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "Window Highlight"
        window.minSize = NSSize(width: 390, height: 310)
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
        loadPreferences()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        borderCheckbox.target = self
        borderCheckbox.action = #selector(borderEnabledChanged)

        let colorRow = NSStackView()
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 12
        colorRow.addArrangedSubview(NSTextField(labelWithString: "枠色"))
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.color = Preferences.shared.borderColor
        colorWell.controlSize = .large
        colorRow.addArrangedSubview(colorWell)

        let widthRow = NSStackView()
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 12
        widthRow.addArrangedSubview(NSTextField(labelWithString: "太さ"))
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.onWheelStep = { [weak self] step in
            self?.adjustWidth(by: step)
        }
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthRow.addArrangedSubview(widthSlider)
        widthRow.addArrangedSubview(widthLabel)

        dimCheckbox.target = self
        dimCheckbox.action = #selector(dimEnabledChanged)

        allDisplaysCheckbox.target = self
        allDisplaysCheckbox.action = #selector(applyToAllDisplaysChanged)

        let dimRow = NSStackView()
        dimRow.orientation = .horizontal
        dimRow.alignment = .centerY
        dimRow.spacing = 12
        dimRow.addArrangedSubview(NSTextField(labelWithString: "暗さ"))
        dimSlider.target = self
        dimSlider.action = #selector(dimAlphaChanged)
        dimSlider.onWheelStep = { [weak self] step in
            self?.adjustDimAlpha(by: step)
        }
        dimSlider.translatesAutoresizingMaskIntoConstraints = false
        dimRow.addArrangedSubview(dimSlider)
        dimRow.addArrangedSubview(dimLabel)

        let permissionButton = NSButton(
            title: "アクセシビリティ許可を確認",
            target: self,
            action: #selector(openPrivacySettings)
        )
        permissionButton.bezelStyle = .rounded

        stack.addArrangedSubview(borderCheckbox)
        stack.addArrangedSubview(colorRow)
        stack.addArrangedSubview(widthRow)
        stack.addArrangedSubview(dimCheckbox)
        stack.addArrangedSubview(dimRow)
        stack.addArrangedSubview(allDisplaysCheckbox)
        stack.addArrangedSubview(permissionButton)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            widthSlider.widthAnchor.constraint(equalToConstant: 180),
            dimSlider.widthAnchor.constraint(equalToConstant: 180)
        ])
    }

    private func loadPreferences() {
        borderCheckbox.state = Preferences.shared.borderEnabled ? .on : .off
        widthSlider.doubleValue = Double(Preferences.shared.borderWidth)
        dimCheckbox.state = Preferences.shared.dimEnabled ? .on : .off
        dimSlider.doubleValue = Double((Preferences.shared.dimAlpha * 100).rounded())
        allDisplaysCheckbox.state = Preferences.shared.applyToAllDisplays ? .on : .off
        updateWidthLabel()
        updateDimLabel()
        updateBorderControlState()
    }

    private func updateWidthLabel() {
        widthLabel.stringValue = "\(Int(widthSlider.doubleValue.rounded())) px"
    }

    private func updateDimLabel() {
        dimLabel.stringValue = "\(Int(dimSlider.doubleValue.rounded()))%"
    }

    @objc private func colorChanged() {
        Preferences.shared.borderColor = colorWell.color
    }

    @objc private func borderEnabledChanged() {
        Preferences.shared.borderEnabled = borderCheckbox.state == .on
        updateBorderControlState()
    }

    @objc private func widthChanged() {
        setWidth(widthSlider.doubleValue.rounded())
    }

    private func adjustWidth(by step: Double) {
        setWidth(widthSlider.doubleValue.rounded() + step)
    }

    private func setWidth(_ value: Double) {
        let clamped = min(widthSlider.maxValue, max(widthSlider.minValue, value))
        Preferences.shared.borderWidth = CGFloat(clamped)
        widthSlider.doubleValue = clamped
        updateWidthLabel()
    }

    @objc private func dimEnabledChanged() {
        Preferences.shared.dimEnabled = dimCheckbox.state == .on
    }

    @objc private func applyToAllDisplaysChanged() {
        Preferences.shared.applyToAllDisplays = allDisplaysCheckbox.state == .on
    }

    @objc private func dimAlphaChanged() {
        setDimAlpha(dimSlider.doubleValue.rounded())
    }

    private func adjustDimAlpha(by step: Double) {
        setDimAlpha(dimSlider.doubleValue.rounded() + step)
    }

    private func setDimAlpha(_ value: Double) {
        let clamped = min(dimSlider.maxValue, max(dimSlider.minValue, value))
        Preferences.shared.dimAlpha = CGFloat(clamped / 100)
        dimSlider.doubleValue = clamped
        updateDimLabel()
    }

    private func updateBorderControlState() {
        let enabled = borderCheckbox.state == .on
        colorWell.isEnabled = enabled
        widthSlider.isEnabled = enabled
        widthLabel.textColor = enabled ? .labelColor : .secondaryLabelColor
    }

    @objc private func openPrivacySettings() {
        AccessibilityWindowReader().requestPermissionIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let reader = AccessibilityWindowReader()
    private let overlay = OverlayController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let enabledItem = NSMenuItem(title: "", action: #selector(toggleEnabled), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "設定...", action: #selector(openPreferences), keyEquivalent: ",")
    private let statusInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openPrivacySettings), keyEquivalent: "")
    private lazy var preferencesWindowController = PreferencesWindowController()
    private var timer: Timer?
    private var lastStatus = "未検出"
    private var lastWrittenStatus = ""
    private var lastOverlayState: OverlayRenderState?
    private var overlayHidden = true
    private let normalRefreshInterval: TimeInterval = 0.15
    private let burstRefreshInterval: TimeInterval = 0.05
    private let burstDuration: TimeInterval = 0.6
    private var burstUntil = Date.distantPast
    private var currentTimerInterval: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        reader.requestPermissionIfNeeded()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        scheduleOverlayTimer(interval: normalRefreshInterval)
        refreshOverlay(force: true)

        if CommandLine.arguments.contains("--settings") {
            openPreferences()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        overlay.hide()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: "Window Highlight")
            button.toolTip = "Window Highlight"
        }
        configureMenu()
    }

    private func configureMenu() {
        enabledItem.target = self
        settingsItem.target = self
        statusInfoItem.isEnabled = false
        permissionItem.target = self

        statusMenu.delegate = self
        statusMenu.addItem(enabledItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(statusInfoItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(settingsItem)
        statusMenu.addItem(permissionItem)
        statusMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusMenu.addItem(quitItem)

        updateMenuItems()
        statusItem.menu = statusMenu
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuItems()
    }

    private func updateMenuItems() {
        enabledItem.title = Preferences.shared.enabled ? "ハイライトを停止" : "ハイライトを開始"
        statusInfoItem.title = "対象: \(lastStatus)"
        permissionItem.title = reader.isTrusted ? "アクセシビリティ許可済み" : "アクセシビリティ許可が必要"
    }

    private func setStatus(_ status: String) {
        lastStatus = status
        guard status != lastWrittenStatus else { return }
        lastWrittenStatus = status
        try? status.write(
            toFile: "/tmp/window-highlight-status.txt",
            atomically: true,
            encoding: .utf8
        )
    }

    @objc private func activeApplicationChanged() {
        beginBurstRefresh()
        refreshOverlay(force: true)
    }

    @objc private func refreshOverlayFromTimer() {
        updateTimerModeIfNeeded()
        refreshOverlay(force: false)
    }

    private func beginBurstRefresh() {
        burstUntil = Date().addingTimeInterval(burstDuration)
        scheduleOverlayTimer(interval: burstRefreshInterval)
    }

    private func updateTimerModeIfNeeded() {
        if Date() > burstUntil && currentTimerInterval != normalRefreshInterval {
            scheduleOverlayTimer(interval: normalRefreshInterval)
        }
    }

    private func scheduleOverlayTimer(interval: TimeInterval) {
        guard currentTimerInterval != interval else {
            return
        }

        timer?.invalidate()
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(refreshOverlayFromTimer),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = interval >= normalRefreshInterval ? 0.03 : 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentTimerInterval = interval
    }

    private func refreshOverlay(force: Bool) {
        guard Preferences.shared.enabled else {
            setStatus("停止中")
            hideOverlayIfNeeded()
            return
        }

        guard let activeWindow = reader.activeWindowBounds() else {
            setStatus(reader.isTrusted ? "アクティブウィンドウ未検出" : "未検出（アクセシビリティ未許可）")
            hideOverlayIfNeeded()
            return
        }

        setStatus("\(activeWindow.applicationName) \(Int(activeWindow.frame.minX)),\(Int(activeWindow.frame.minY)) \(Int(activeWindow.frame.width))x\(Int(activeWindow.frame.height))")
        let color = Preferences.shared.borderColor
        let width = Preferences.shared.borderWidth
        let borderEnabled = Preferences.shared.borderEnabled
        let dimEnabled = Preferences.shared.dimEnabled
        let dimAlpha = Preferences.shared.dimAlpha
        let applyToAllDisplays = Preferences.shared.applyToAllDisplays
        let state = OverlayRenderState(
            frame: activeWindow.frame,
            color: color,
            width: width,
            borderEnabled: borderEnabled,
            dimEnabled: dimEnabled,
            dimAlpha: dimAlpha,
            applyToAllDisplays: applyToAllDisplays
        )
        guard force || state != lastOverlayState || overlayHidden else {
            return
        }

        overlay.show(
            around: activeWindow.frame,
            color: color,
            width: width,
            borderEnabled: borderEnabled,
            dimEnabled: dimEnabled,
            dimAlpha: dimAlpha,
            applyToAllDisplays: applyToAllDisplays
        )
        lastOverlayState = state
        overlayHidden = false
    }

    @objc private func toggleEnabled() {
        Preferences.shared.enabled.toggle()
        if !Preferences.shared.enabled {
            hideOverlayIfNeeded()
        } else {
            beginBurstRefresh()
            refreshOverlay(force: true)
        }
        updateMenuItems()
    }

    @objc private func openPreferences() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.setActivationPolicy(.regular)
            let controller = self.preferencesWindowController
            controller.onClose = {
                NSApp.setActivationPolicy(.accessory)
            }
            controller.showWindow(nil)
            controller.window?.center()
            controller.window?.makeKeyAndOrderFront(nil)
            controller.window?.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
    }

    @objc private func openPrivacySettings() {
        reader.requestPermissionIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        updateMenuItems()
    }

    private func hideOverlayIfNeeded() {
        guard !overlayHidden else {
            return
        }

        overlay.hide()
        overlayHidden = true
        lastOverlayState = nil
    }
}

@main
private enum WindowHighlightApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
