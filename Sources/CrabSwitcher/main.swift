import AppKit
import Carbon
import ServiceManagement

// MARK: - App delegate

final class CrabSwitcherApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let switcher = KeyboardLayoutSwitcher()
    private let menu = NSMenu()
    private let permissionStatusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openPermissionsItem = NSMenuItem(
        title: "Open Input Monitoring Settings…",
        action: #selector(openPrivacySettings),
        keyEquivalent: ""
    )
    private let launchAtLoginItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var nsEventMonitor: Any?
    private var fnPressed = false
    private var workspaceObserver: Any?
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        refreshStatusIcon()
        CGRequestListenEventAccess()
        attemptInstallAndUpdateUI()
        installNSEventFallback()
        installWorkspaceObserver()
        setupInitialLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        uninstallFnMonitor()
        if let monitor = nsEventMonitor {
            NSEvent.removeMonitor(monitor)
            nsEventMonitor = nil
        }
        permissionRetryTimer?.invalidate()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    /// Parallel detection path. NSEvent's global monitor uses different
    /// plumbing than CGEventTap, so if the tap is being filtered we may
    /// still catch the Fn key here.
    private func installNSEventFallback() {
        if nsEventMonitor != nil { return }
        nsEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            let isNowDown = event.modifierFlags.contains(.function)
            if isNowDown && !self.fnPressed {
                DispatchQueue.main.async { self.toggleLanguage() }
            }
            self.fnPressed = isNowDown
        }
    }

    // MARK: - Menu

    private func configureMenu() {
        let switchItem = NSMenuItem(
            withTitle: "Switch Language Now",
            action: #selector(toggleLanguageNow),
            keyEquivalent: ""
        )
        menu.addItem(switchItem)
        menu.addItem(NSMenuItem.separator())
        permissionStatusItem.isEnabled = false
        menu.addItem(permissionStatusItem)
        openPermissionsItem.target = self
        menu.addItem(openPermissionsItem)
        menu.addItem(NSMenuItem.separator())
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            withTitle: "Quit CrabSwitcher",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        attemptInstallAndUpdateUI()
        updateLanguageTitle()
        updateLaunchAtLoginState()
    }

    func menuDidClose(_ menu: NSMenu) {
        refreshStatusIcon()
    }

    // MARK: - Icon

    private func refreshStatusIcon() {
        let icon = CrabStatusIcon.make()
        statusItem.button?.image = icon
        statusItem.button?.alternateImage = icon
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "CrabSwitcher (\(switcher.currentShortTitle()))"
    }

    private func updateLanguageTitle() {
        statusItem.button?.toolTip = "CrabSwitcher (\(switcher.currentShortTitle()))"
    }

    // MARK: - Permissions

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.attemptInstallAndUpdateUI()
        }
    }

    /// Source of truth: try to install the tap. If it works, we have permission.
    /// `CGPreflightListenEventAccess()` is unreliable across rebuilds (binary hash
    /// changes invalidate TCC's cached grant even though the toggle still appears
    /// enabled in System Settings).
    private func attemptInstallAndUpdateUI() {
        let installed = installFnMonitorIfNeeded()

        if installed {
            permissionStatusItem.title = "🟢 Fn key monitoring active"
            openPermissionsItem.isHidden = true
            stopPermissionRetry()
        } else {
            permissionStatusItem.title = "🔴 Input Monitoring permission needed"
            openPermissionsItem.isHidden = false
            startPermissionRetry()
        }
    }

    private func startPermissionRetry() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.attemptInstallAndUpdateUI()
        }
    }

    private func stopPermissionRetry() {
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
    }

    // MARK: - Event tap (Fn key)

    @discardableResult
    private func installFnMonitorIfNeeded() -> Bool {
        if eventTap != nil { return true }

        if let (tap, source) = createTap(at: .cghidEventTap) {
            eventTap = tap
            eventTapSource = source
            return true
        }
        if let (tap, source) = createTap(at: .cgSessionEventTap) {
            eventTap = tap
            eventTapSource = source
            return true
        }
        return false
    }

    private func createTap(at location: CGEventTapLocation) -> (CFMachPort, CFRunLoopSource)? {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let app = Unmanaged<CrabSwitcherApp>.fromOpaque(refcon).takeUnretainedValue()
                return app.handleEventTap(type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            return nil
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if !CGEvent.tapIsEnabled(tap: tap) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
            return nil
        }

        return (tap, source)
    }

    private func uninstallFnMonitor() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        fnPressed = false
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let isNowDown = event.flags.contains(.maskSecondaryFn)
        if isNowDown && !fnPressed {
            DispatchQueue.main.async { [weak self] in
                self?.toggleLanguage()
            }
        }
        fnPressed = isNowDown
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Language switching

    private func toggleLanguage() {
        switcher.toggleBetweenEnglishAndRussian()
        updateLanguageTitle()
    }

    @objc private func toggleLanguageNow() { toggleLanguage() }

    @objc private func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at Login

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Failed to toggle Launch at Login: \(error)")
        }
        updateLaunchAtLoginState()
    }

    private func updateLaunchAtLoginState() {
        launchAtLoginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func setupInitialLaunchAtLogin() {
        let key = "hasSetInitialLaunchAtLogin"
        if !UserDefaults.standard.bool(forKey: key) {
            let service = SMAppService.mainApp
            if service.status != .enabled {
                try? service.register()
            }
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

// MARK: - NSMenuItem convenience

private extension NSMenuItem {
    convenience init(withTitle title: String, action: Selector?, keyEquivalent: String) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = nil
    }
}

// MARK: - Keyboard layout switcher

final class KeyboardLayoutSwitcher {
    private let preferredEnglishIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
    private let preferredRussianIDs = ["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"]

    func toggleBetweenEnglishAndRussian() {
        guard let current = currentInputSource() else { return }

        if isRussianSource(current) {
            if let en = findByPreferredIDs(preferredEnglishIDs) ?? selectableSources().first(where: isEnglishSource) {
                TISSelectInputSource(en)
            }
        } else {
            if let ru = findByPreferredIDs(preferredRussianIDs) ?? selectableSources().first(where: isRussianSource) {
                TISSelectInputSource(ru)
            }
        }
    }

    func currentShortTitle() -> String {
        guard let src = currentInputSource() else { return "??" }
        return isRussianSource(src) ? "RU" : "EN"
    }

    private func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func findByPreferredIDs(_ ids: [String]) -> TISInputSource? {
        let sources = selectableSources()
        for id in ids {
            if let match = sources.first(where: { sourceID($0) == id }) { return match }
        }
        return nil
    }

    private func selectableSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list.filter { boolProp($0, kTISPropertyInputSourceIsEnabled) && boolProp($0, kTISPropertyInputSourceIsSelectCapable) }
    }

    private func isRussianSource(_ src: TISInputSource) -> Bool {
        let id = sourceID(src).lowercased()
        if id.contains("russian") || id.contains(".ru") { return true }
        if stringProp(src, kTISPropertyLocalizedName)?.lowercased().contains("russian") == true { return true }
        return (stringArrayProp(src, kTISPropertyInputSourceLanguages)).contains { $0.hasPrefix("ru") }
    }

    private func isEnglishSource(_ src: TISInputSource) -> Bool {
        let id = sourceID(src).lowercased()
        if id.contains(".abc") || id.contains(".us") || id.contains("english") { return true }
        let name = stringProp(src, kTISPropertyLocalizedName)?.lowercased() ?? ""
        if name == "abc" || name.contains("english") { return true }
        return (stringArrayProp(src, kTISPropertyInputSourceLanguages)).contains { $0.hasPrefix("en") }
    }

    private func sourceID(_ src: TISInputSource) -> String {
        stringProp(src, kTISPropertyInputSourceID) ?? ""
    }

    private func stringProp(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func stringArrayProp(_ src: TISInputSource, _ key: CFString) -> [String] {
        guard let raw = TISGetInputSourceProperty(src, key) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
    }

    private func boolProp(_ src: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(src, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}

// MARK: - Crab icon (resolution-independent template image)

enum CrabStatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width / 18.0

            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.1 * s)
            ctx.setLineCap(.round)

            // body
            let bodyPath = NSBezierPath(
                roundedRect: NSRect(x: 4.5 * s, y: 4.0 * s, width: 9.0 * s, height: 6.5 * s),
                xRadius: 3.0 * s, yRadius: 3.0 * s
            )
            bodyPath.fill()

            // eyestalks
            func line(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) {
                ctx.move(to: CGPoint(x: ax * s, y: ay * s))
                ctx.addLine(to: CGPoint(x: bx * s, y: by * s))
                ctx.strokePath()
            }
            line(6.7, 10.5, 6.7, 11.8)
            line(11.3, 10.5, 11.3, 11.8)

            // eyes
            func dot(_ cx: CGFloat, _ cy: CGFloat, r: CGFloat) {
                ctx.fillEllipse(in: CGRect(x: (cx - r) * s, y: (cy - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            dot(6.7, 12.5, r: 0.8)
            dot(11.3, 12.5, r: 0.8)

            // legs (3 pairs)
            let legOffsetsY: [(CGFloat, CGFloat)] = [(8.5, 9.4), (7.5, 8.1), (6.6, 6.8)]
            for (ly, ry) in legOffsetsY {
                line(4.8, ly, 2.2, ry)
                line(13.2, ly, 15.8, ry)
            }

            // arms to claws
            ctx.setLineWidth(1.3 * s)
            line(4.5, 9.2, 2.5, 12.2)
            line(13.5, 9.2, 15.5, 12.2)

            // claws (filled triangles)
            func claw(tip: CGPoint, a: CGPoint, b: CGPoint) {
                ctx.move(to: CGPoint(x: tip.x * s, y: tip.y * s))
                ctx.addLine(to: CGPoint(x: a.x * s, y: a.y * s))
                ctx.addLine(to: CGPoint(x: b.x * s, y: b.y * s))
                ctx.closePath()
                ctx.fillPath()
            }
            claw(tip: CGPoint(x: 1.2, y: 12.5), a: CGPoint(x: 2.6, y: 14.8), b: CGPoint(x: 4.2, y: 12.8))
            claw(tip: CGPoint(x: 16.8, y: 12.5), a: CGPoint(x: 15.4, y: 14.8), b: CGPoint(x: 13.8, y: 12.8))

            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = CrabSwitcherApp()

@main
struct CrabSwitcherMain {
    static func main() {
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
