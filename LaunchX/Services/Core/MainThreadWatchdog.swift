import Foundation

// MARK: - 主线程看门狗
//
// 背景：macOS 在用 Caps Lock 切换中/英文输入法时，系统会同步走一条
// `TSMAdjustCapsLockPressAndHold → MessageTracerLogDidSwitch → analytics_send_event_internal`
// 的遥测路径（JSON 序列化 + 同步 XPC 发送）。当用户反复/长按 Caps Lock，叠加
// analyticsd 响应迟缓或长期运行后内存膨胀，这条同步遥测会把主线程彻底卡死，
// 表现为应用无响应、CPU 飙升。
//
// 本看门狗在【独立后台队列】上周期性向主线程派发心跳，若主线程长时间
//（超过 stallThreshold）无法响应心跳，即判定主线程阻塞，自动停止会向主线程
// RunLoop 投递回调的 CGEventTap，打破「按键 → tap 回调叠加遥测」的恶性循环。

final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    /// 检测间隔（秒）。后台定时器每这么久评估一次。
    let checkInterval: TimeInterval = 2.0
    /// 主线程无响应超过该阈值即判定阻塞（秒）。
    /// 正常主线程任务都是毫秒级，5s 足够保守、不会误伤正常操作。
    let stallThreshold: TimeInterval = 5.0
    /// 启动后的宽限期（秒），避免启动/刚从睡眠恢复时误判。
    let warmupGrace: TimeInterval = 20.0
    /// 触发保护后的冷却时间（秒），避免在主线程持续卡顿时反复打日志/触发。
    let retriggerCooldown: TimeInterval = 120.0

    private let queue = DispatchQueue(label: "com.launchx.mainthread.watchdog")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    /// 最近一次主线程心跳时间（由主线程心跳任务更新）。
    private var lastMainThreadTick: Date = Date()
    /// 最近一次触发保护的时间（用于冷却判断）。
    private var lastFiredAt: Date?
    /// 启动时刻，用于 warmup。
    private var startedAt: Date = Date()
    /// 是否已至少触发过一次保护。
    private(set) var hasFired = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self = self, self.timer == nil else { return }
            self.startedAt = Date()
            self.lastMainThreadTick = Date()
            self.hasFired = false

            // 主线程心跳任务：主线程空闲时会被调度执行，更新 tick。
            DispatchQueue.main.async { [weak self] in
                self?.recordTick()
            }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.checkInterval, repeating: self.checkInterval)
            timer.setEventHandler { [weak self] in self?.check() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    // MARK: - Internals

    private func recordTick() {
        lock.lock()
        lastMainThreadTick = Date()
        lock.unlock()
    }

    private func check() {
        // 1. 往主线程投递一次心跳。主线程若卡住，该 async 块不会被执行，tick 不会更新。
        DispatchQueue.main.async { [weak self] in
            self?.recordTick()
        }

        // 2. 评估主线程响应延迟。
        lock.lock()
        let elapsed = Date().timeIntervalSince(lastMainThreadTick)
        let sinceStart = Date().timeIntervalSince(startedAt)
        let lastFire = lastFiredAt
        let alreadyFired = hasFired
        lock.unlock()

        // 宽限期内不判定。
        if sinceStart < warmupGrace { return }
        // 主线程响应正常。
        if elapsed < stallThreshold { return }
        // 冷却期内不重复触发。
        if let last = lastFire, Date().timeIntervalSince(last) < retriggerCooldown { return }

        fireProtection(elapsed: elapsed, alreadyFired: alreadyFired)
    }

    /// 触发保护。注意：这里运行在后台队列，绝不能调用必须在主线程使用的 API
    /// （如 NSEvent.removeMonitor）。只做线程安全的操作。
    private func fireProtection(elapsed: TimeInterval, alreadyFired: Bool) {
        lock.lock()
        hasFired = true
        lastFiredAt = Date()
        lock.unlock()

        let prefix = alreadyFired ? "⚠️ 主线程持续阻塞" : "⚠️ 主线程阻塞"
        print(
            "\(prefix) \(String(format: "%.1f", elapsed))s，"
            + "疑似系统输入法切换遥测(Caps Lock)卡住主线程，"
            + "已自动暂停 CGEventTap 以尝试恢复响应。"
        )

        // CGEvent.tapEnable 与 mach port 操作线程安全；
        // 它是 Caps Lock 路径上唯一会向主线程 RunLoop 投递回调的组件，
        // 停掉它即可打断「按键 → tap 回调 → 叠加 TSM 遥测」的恶性循环。
        KeyRemapService.shared.emergencyStopByWatchdog()

        // 双击唤起的 NSEvent monitor 必须在主线程移除；主线程此刻卡住，
        // 这里只能排队，待主线程恢复后执行，作为额外减负。
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            HotKeyService.shared.stopDoubleTapMonitoring()
        }
    }
}

// MARK: - flagsChanged 风暴检测器
//
// 在事件回调（CGEventTap 回调 / NSEvent monitor）进入主线程时做早期预防：
// 若 1 秒内 flagsChanged 次数超过阈值（典型场景：Caps Lock 抖动、输入法切换回环），
// 主动暂停监听一段时间，避免在系统遥测卡死前就把主线程拖垮。
// 与 MainThreadWatchdog 互补：风暴检测是「卡死前的预防」，watchdog 是「卡死后的兜底」。

final class FlagsStormDetector {
    private var timestamps: [Date] = []
    private let lock = NSLock()

    let window: TimeInterval
    let threshold: Int

    /// - Parameters:
    ///   - window: 滑动窗口长度（秒），默认 1.0s。
    ///   - threshold: 窗口内事件数超过该值即判定为风暴，默认 1 秒 30 次。
    init(window: TimeInterval = 1.0, threshold: Int = 30) {
        self.window = window
        self.threshold = threshold
    }

    /// 记录一次 flagsChanged 事件，返回当前是否已触发风暴阈值。
    /// CGEventTap 回调为单线程串行，NSEvent monitor 回调也在主线程；
    /// 这里加锁仅为跨组件复用时的安全性。
    @discardableResult
    func recordAndCheck() -> Bool {
        let now = Date()
        lock.lock()
        timestamps.removeAll { now.timeIntervalSince($0) > window }
        timestamps.append(now)
        let isStorm = timestamps.count > threshold
        lock.unlock()
        return isStorm
    }

    func reset() {
        lock.lock()
        timestamps.removeAll()
        lock.unlock()
    }
}
