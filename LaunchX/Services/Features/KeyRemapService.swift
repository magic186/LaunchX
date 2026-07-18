import Cocoa
import Carbon

class KeyRemapService {
    static let shared = KeyRemapService()

    // MARK: - State
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightCommandPressed = false

    // MARK: - Settings
    private var batchUpdate = false

    // MARK: - Watchdog / 风暴保护
    private let stormDetector = FlagsStormDetector()
    /// 风暴暂停持续时长（秒）。
    private let stormPauseSeconds: TimeInterval = 30
    /// 被主线程看门狗紧急停止（不自动恢复，需用户在设置里手动重开）。
    private(set) var watchdogPaused = false
    /// 因 flagsChanged 风暴临时暂停（到点自动恢复）。
    private var stormPaused = false
    private var stormResumeWork: DispatchWorkItem?

    var hyperKeyEnabled = false {
        didSet { if !batchUpdate { updateEventTap() } }
    }

    var quoteSwapEnabled = false {
        didSet { if !batchUpdate { updateEventTap() } }
    }

    // MARK: - Accessibility Permission

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var isEventTapActive: Bool {
        eventTap != nil && CGEvent.tapIsEnabled(tap: eventTap!)
    }

    private init() {}

    // MARK: - Batch Update

    func applySettings(hyper: Bool, quote: Bool) {
        // 用户主动调整键映射设置即视为「解除看门狗暂停」，
        // 这样在设置页重新开关 Hyper/引号交换就能恢复被看门狗停掉的 tap。
        if watchdogPaused {
            watchdogPaused = false
            print("KeyRemapService: 用户重新设置键映射，解除看门狗暂停")
        }
        batchUpdate = true
        hyperKeyEnabled = hyper
        quoteSwapEnabled = quote
        batchUpdate = false
        // Start/stop CGEventTap for Hyper+Quote
        updateEventTap()
    }

    // MARK: - CGEventTap Lifecycle

    private func needsEventTap() -> Bool {
        (hyperKeyEnabled || quoteSwapEnabled) && hasAccessibilityPermission
    }

    private func updateEventTap() {
        if needsEventTap() {
            stopEventTap()
            startEventTap()
        } else {
            stopEventTap()
        }
    }

    private func startEventTap() {
        guard eventTap == nil else { return }
        // 看门狗/风暴暂停期间不重启 tap（避免立即再次卡死）
        guard !watchdogPaused, !stormPaused else { return }
        guard hasAccessibilityPermission else { return }
        guard hyperKeyEnabled || quoteSwapEnabled else { return }

        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
        )

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else {
                        return Unmanaged.passUnretained(event)
                    }
                    let service = Unmanaged<KeyRemapService>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return service.handleEvent(proxy: proxy, type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            print("KeyRemapService: Failed to create CGEventTap")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("KeyRemapService: CGEventTap started (hyper=\(hyperKeyEnabled), quote=\(quoteSwapEnabled))")
    }

    func stopEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        rightCommandPressed = false
        // 清理风暴保护状态（但不重置 watchdogPaused——那是用户级状态，需用户手动重开）
        stormResumeWork?.cancel()
        stormResumeWork = nil
        stormPaused = false
        stormDetector.reset()
        print("KeyRemapService: CGEventTap stopped")
    }

    // MARK: - 主线程看门狗 / 风暴保护

    /// 由 MainThreadWatchdog 在后台线程调用：立即停止 CGEventTap（操作线程安全），
    /// 并标记为「看门狗暂停」，阻止后续自动重启，直至用户手动重开。
    func emergencyStopByWatchdog() {
        watchdogPaused = true
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        print("KeyRemapService: ⚠️ 被主线程看门狗紧急停止（watchdogPaused=true）")
    }

    /// 用户在设置里手动重新启用键映射时调用，解除看门狗暂停状态。
    func resetWatchdogPause() {
        guard watchdogPaused else { return }
        watchdogPaused = false
        print("KeyRemapService: 看门狗暂停已解除")
        updateEventTap()
    }

    /// event tap 回调里检测到 flagsChanged 风暴：临时停 tap 一段时间再自动恢复。
    private func handleFlagsStorm() {
        guard !stormPaused else { return }
        stormPaused = true
        stormDetector.reset()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        print(
            "KeyRemapService: ⚠️ 检测到 flagsChanged 风暴（疑似 Caps Lock 回环），暂停 event tap \(Int(stormPauseSeconds))s"
        )

        let work = DispatchWorkItem { [weak self] in
            self?.resumeFromStorm()
        }
        stormResumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + stormPauseSeconds, execute: work)
    }

    private func resumeFromStorm() {
        stormPaused = false
        stormResumeWork = nil
        // 若看门狗也已暂停，则不自动恢复（避免再次卡死）
        guard !watchdogPaused else {
            print("KeyRemapService: 风暴暂停结束，但看门狗仍处于暂停状态，保持 tap 停用")
            return
        }
        if let tap = eventTap, hyperKeyEnabled || quoteSwapEnabled {
            CGEvent.tapEnable(tap: tap, enable: true)
            print("KeyRemapService: 风暴暂停结束，恢复 event tap")
        }
    }

    // MARK: - CGEventTap Callback

    private func handleEvent(
        proxy: CGEventTapProxy, type: CGEventType, event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            print("KeyRemapService: EventTap disabled, re-enabling")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 风暴保护：高频 flagsChanged（疑似 Caps Lock 输入法切换遥测回环）时主动暂停 tap，
        // 避免在系统遥测卡死前就把主线程 RunLoop 拖垮。
        if type == .flagsChanged, stormDetector.recordAndCheck() {
            handleFlagsStorm()
        }

        // Track Right Command state + inject Hyper modifiers into flagsChanged
        if hyperKeyEnabled, type == .flagsChanged, keyCode == 0x36 {
            updateHyperState(event: event)
            if rightCommandPressed {
                // Also tell the system that Ctrl+Shift+Option are pressed
                event.flags = event.flags.union([
                    .maskControl, .maskShift, .maskAlternate,
                ])
            }
        }

        // Inject Hyper modifiers into all keyDown events while Right Command held
        if hyperKeyEnabled, rightCommandPressed, type == .keyDown {
            event.flags = event.flags.union([
                .maskControl, .maskShift, .maskAlternate,
            ])
        }

        if quoteSwapEnabled, type == .keyDown, keyCode == 0x27 {
            handleQuoteSwap(event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Hyper Key (Right Command → Cmd+Ctrl+Shift+Option)

    private let NX_DEVICERCMDKEYMASK: UInt64 = 0x10

    private func updateHyperState(event: CGEvent) {
        let rawFlags = event.flags.rawValue
        let isRightDown = (rawFlags & NX_DEVICERCMDKEYMASK) != 0

        if isRightDown, !rightCommandPressed {
            rightCommandPressed = true
            print("KeyRemapService: Hyper ON (Right ⌘ held)")
        } else if !isRightDown, rightCommandPressed {
            rightCommandPressed = false
            print("KeyRemapService: Hyper OFF")
        }
    }

    // MARK: - Quote Swap (' ↔ ")

    private func handleQuoteSwap(event: CGEvent) {
        if event.flags.contains(.maskShift) {
            event.flags.subtract(.maskShift)
            print("KeyRemapService: Quote swap: \" → '")
        } else {
            event.flags.insert(.maskShift)
            print("KeyRemapService: Quote swap: ' → \"")
        }
    }

    // MARK: - Process Helper

    @discardableResult
    private func runProcess(_ executable: String, arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch {
            print("KeyRemapService: \(executable) failed: \(error)")
            return ""
        }
    }
}
