import AppKit
import Carbon
import ServiceManagement

// MARK: - App delegate

final class CrabSwitcherApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum FnEventSource: Hashable {
        case eventTap
        case nsEvent
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let switcher = KeyboardLayoutSwitcher()
    private let menu = NSMenu()
    private let languagesMenu = NSMenu(title: "Languages")
    private lazy var languagesItem: NSMenuItem = {
        let item = NSMenuItem(title: "Languages", action: nil, keyEquivalent: "")
        item.submenu = languagesMenu
        return item
    }()
    private let hotkeyLabel = NSTextField(labelWithString: "")
    private lazy var hotkeyRowView: HotkeyMenuRowView = {
        let rowHeight: CGFloat = 22
        let row = HotkeyMenuRowView(frame: NSRect(x: 0, y: 0, width: 220, height: rowHeight))
        hotkeyLabel.font = .menuFont(ofSize: 0)
        hotkeyLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(hotkeyLabel)
        NSLayoutConstraint.activate([
            hotkeyLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 23),
            hotkeyLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            hotkeyLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor, constant: -2),
        ])
        row.label = hotkeyLabel
        row.onClick = { [weak self] in self?.recordHotkey() }
        return row
    }()
    private lazy var hotkeyItem: NSMenuItem = {
        let item = NSMenuItem()
        item.view = hotkeyRowView
        return item
    }()
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
    private var activeFnSources: Set<FnEventSource> = []
    private var lastShortcutTimestamp: TimeInterval?
    private var workspaceObserver: Any?
    private var permissionRetryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureStatusItem()
        CGRequestListenEventAccess()
        attemptInstallAndUpdateUI()
        installNSEventFallback()
        installWorkspaceObserver()
        setupInitialLaunchAtLogin()
    }

    func applicationWillTerminate(_ notification: Notification) {
        uninstallEventTap()
        uninstallNSEventFallback()
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
        nsEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .systemDefined]
        ) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                self?.handleNSEvent(event)
            }
        }
    }

    private func uninstallNSEventFallback() {
        guard let monitor = nsEventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        nsEventMonitor = nil
    }

    /// The event tap and NSEvent monitor report the same physical Fn press with
    /// matching timestamps. Track both sources and coalesce those duplicate
    /// reports without delaying a later physical press.
    private func handleFnStateChange(
        isNowDown: Bool,
        source: FnEventSource,
        timestamp: TimeInterval
    ) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard isNowDown else {
            // A release reported by either API proves that the physical key is
            // up. Clearing both avoids a stale source blocking the next press.
            activeFnSources.removeAll()
            return
        }
        guard activeFnSources.insert(source).inserted else { return }
        guard activeFnSources.count == 1 else { return }

        if let lastTimestamp = lastShortcutTimestamp,
           abs(timestamp - lastTimestamp) < 0.08 {
            return
        }
        lastShortcutTimestamp = timestamp
        toggleLanguage()
    }

    private static func isEjectKeyDown(_ event: NSEvent) -> Bool {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else { return false }
        let data1 = event.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        return keyCode == 14 && isKeyDown
    }

    private func handleNSEvent(_ event: NSEvent) {
        if isRecordingHotkey { return }

        if event.type == .keyDown, !event.isARepeat {
            let flags = event.cgEvent?.flags
                ?? CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            if selectedHotkey.matches(keyCode: event.keyCode, flags: flags) {
                triggerShortcut(timestamp: event.timestamp)
            }
            return
        }

        if event.type == .systemDefined,
           selectedHotkey.isEject,
           Self.isEjectKeyDown(event) {
            triggerShortcut(timestamp: event.timestamp)
            return
        }

        if event.type == .flagsChanged, selectedHotkey.isFnOnly {
            handleFnStateChange(
                isNowDown: event.modifierFlags.contains(.function),
                source: .nsEvent,
                timestamp: event.timestamp
            )
        }
    }

    private func triggerShortcut(timestamp: TimeInterval) {
        if let lastTimestamp = lastShortcutTimestamp,
           abs(timestamp - lastTimestamp) < 0.08 {
            return
        }
        lastShortcutTimestamp = timestamp
        toggleLanguage()
    }

    // MARK: - Menu

    private func configureMenu() {
        let switchItem = NSMenuItem(
            title: "Switch Language Now",
            action: #selector(toggleLanguageNow),
            keyEquivalent: ""
        )
        switchItem.target = self
        menu.addItem(switchItem)
        menu.addItem(languagesItem)
        rebuildLanguagesMenu()
        let hotkeySpacer = NSMenuItem()
        hotkeySpacer.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 6))
        menu.addItem(hotkeySpacer)
        menu.addItem(hotkeyItem)
        updateHotkeyTitle()
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
            title: "Quit CrabSwitcher",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        attemptInstallAndUpdateUI()
        rebuildLanguagesMenu()
        updateHotkeyTitle()
        updateLanguageTitle()
        updateLaunchAtLoginState()
    }

    private var selectedHotkey: CustomHotkey {
        get { CustomHotkey.load() }
        set {
            newValue.save()
            activeFnSources.removeAll()
            lastShortcutTimestamp = nil
            updateHotkeyTitle()
        }
    }

    private var isRecordingHotkey = false

    private func updateHotkeyTitle() {
        hotkeyLabel.stringValue = isRecordingHotkey
            ? "Hotkey: Press any key…"
            : "Hotkey: \(selectedHotkey.title)"
    }

    private func recordHotkey() {
        isRecordingHotkey = true
        updateHotkeyTitle()
        statusItem.button?.toolTip = "Press any key…"
    }


    private func finishRecording(_ hotkey: CustomHotkey?) {
        isRecordingHotkey = false
        updateLanguageTitle()

        if let hotkey {
            if hotkey.isFnOnly && !isDefaultFnBehaviorDisabled {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Disable the default macOS Fn action"
                alert.informativeText = "To use Fn with CrabSwitcher, set ‘Press 🌐 key to’ to ‘Do Nothing’ in System Settings → Keyboard."
                alert.addButton(withTitle: "Open Keyboard Settings")
                alert.addButton(withTitle: "Use Fn Anyway")
                alert.addButton(withTitle: "Cancel")

                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    selectedHotkey = hotkey
                    openKeyboardSettings()
                case .alertSecondButtonReturn:
                    selectedHotkey = hotkey
                default:
                    break
                }
            } else {
                selectedHotkey = hotkey
            }
        }

        updateHotkeyTitle()
    }

    private var isDefaultFnBehaviorDisabled: Bool {
        let appID = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(appID)
        guard let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, appID) as? NSNumber else {
            return false
        }
        return value.intValue == 0
    }

    private func openKeyboardSettings() {
        let pane = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    private func rebuildLanguagesMenu() {
        languagesMenu.removeAllItems()

        let languages = switcher.availableLanguages()
        guard !languages.isEmpty else {
            let item = NSMenuItem(title: "No Languages Available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            languagesMenu.addItem(item)
            return
        }

        let selectedIDs = switcher.selectedLanguageIDs
        let languageFont = NSFont.menuFont(ofSize: 0)
        let rowHeight: CGFloat = 30
        let rowWidth = max(
            180,
            languages.map {
                ceil(($0.name as NSString).size(withAttributes: [.font: languageFont]).width + 60)
            }.max() ?? 180
        )

        for language in languages {
            let item = NSMenuItem()
            let checkbox = NSButton(
                checkboxWithTitle: language.name,
                target: self,
                action: #selector(toggleLanguageSelection(_:))
            )
            checkbox.identifier = NSUserInterfaceItemIdentifier(language.id)
            checkbox.state = selectedIDs.contains(language.id) ? .on : .off
            checkbox.controlSize = .regular
            checkbox.font = languageFont
            checkbox.frame = NSRect(x: 12, y: 0, width: rowWidth - 12, height: rowHeight)
            checkbox.autoresizingMask = [.width, .height]

            let row = LanguageMenuRowView(
                checkbox: checkbox,
                frame: NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight)
            )
            row.addSubview(checkbox)
            item.view = row
            languagesMenu.addItem(item)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if isRecordingHotkey {
            finishRecording(nil)
        } else {
            updateLanguageTitle()
        }
    }

    // MARK: - Icon

    private func configureStatusItem() {
        statusItem.button?.image = CrabStatusIcon.make()
        statusItem.button?.imagePosition = .imageOnly
        updateLanguageTitle()
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
        let installed = installEventTapIfNeeded()

        if installed {
            permissionStatusItem.title = "Hotkey monitoring active"
            openPermissionsItem.isHidden = true
            stopPermissionRetry()
        } else {
            permissionStatusItem.title = "Input Monitoring permission needed"
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

    // MARK: - Event tap (global hotkey)

    @discardableResult
    private func installEventTapIfNeeded() -> Bool {
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
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << 14)
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

    private func uninstallEventTap() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        activeFnSources.removeAll()
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if isRecordingHotkey {
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 53 {
                    DispatchQueue.main.async { [weak self] in self?.finishRecording(nil) }
                    return Unmanaged.passUnretained(event)
                }
                let modOnly: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn]
                let mods = event.flags.rawValue & modOnly.rawValue
                let hotkey = CustomHotkey(keyCode: UInt16(keyCode), modifiers: mods)
                DispatchQueue.main.async { [weak self] in self?.finishRecording(hotkey) }
                return Unmanaged.passUnretained(event)
            }
            if type == .flagsChanged {
                let fnDown = event.flags.contains(.maskSecondaryFn)
                let hasOtherMods = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand]) != []
                if fnDown && !hasOtherMods {
                    DispatchQueue.main.async { [weak self] in self?.finishRecording(.fn) }
                    return Unmanaged.passUnretained(event)
                }
            }
            if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), Self.isEjectKeyDown(nsEvent) {
                DispatchQueue.main.async { [weak self] in self?.finishRecording(.eject) }
                return Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if !isRepeat, selectedHotkey.matches(keyCode: keyCode, flags: event.flags) {
                triggerShortcut(timestamp: TimeInterval(event.timestamp) / 1_000_000_000)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged, selectedHotkey.isFnOnly {
            let isNowDown = event.flags.contains(.maskSecondaryFn)
            handleFnStateChange(
                isNowDown: isNowDown,
                source: .eventTap,
                timestamp: TimeInterval(event.timestamp) / 1_000_000_000
            )
        }

        if type.rawValue == 14, selectedHotkey.isEject {
            if let nsEvent = NSEvent(cgEvent: event), Self.isEjectKeyDown(nsEvent) {
                triggerShortcut(timestamp: TimeInterval(event.timestamp) / 1_000_000_000)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Language switching

    private func toggleLanguage() {
        switcher.selectNextLanguage()
        updateLanguageTitle()
    }

    @objc private func toggleLanguageNow() { toggleLanguage() }

    @objc private func toggleLanguageSelection(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        switcher.toggleLanguageSelection(id: id)
        sender.state = switcher.selectedLanguageIDs.contains(id) ? .on : .off
    }

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
        service.status == .enabled ? try? service.unregister() : try? service.register()
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

// MARK: - Entry point

let app = NSApplication.shared
let delegate = CrabSwitcherApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
