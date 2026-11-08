//
//  HangProbe.swift
//  ehviewer apple
//
//  主线程卡顿探针
//
//  为什么需要它：
//  系统给出的卡死日志（bug_type 509）只包含一份 stackshot，而这台设备上的
//  snapshot 往往没有 shared cache，导致所有系统框架的帧都无法符号化 ——
//  日志里能看到 46 层调用栈，却一层名字都读不出来，只知道卡在 UIKit/SwiftUI 里。
//
//  本探针做两件事：
//    1. 心跳：主线程每 0.5s 打一次点。看门狗线程发现超过 3s 没打点，
//       就把「卡住时正在执行哪个区段」写进可导出的日志文件。
//    2. 慢操作：任何标记了 measure/enter 的同步区段，超过 350ms 记一条 WARN，
//       便于事后按耗时排序，找出真正的时间黑洞。
//
//  设计取舍：刻意不使用 Mach 线程采样（thread_suspend + 栈回溯）。
//  那套东西能拿到栈，但要在别人的栈上做 vm_read，一旦边界判断有误就是新的
//  崩溃源；而我们现在最缺的不是「更细的栈」，而是「到底是哪一段代码」——
//  区段标记足以回答这个问题，且零风险。
//

import Foundation

final class HangProbe: @unchecked Sendable {

    static let shared = HangProbe()

    private struct Section {
        let name: String
        let since: TimeInterval
    }

    private let lock = NSLock()
    private var stack: [Section] = []
    /// 当前可见页面的名字。区段标记只能覆盖我们显式包住的同步调用，
    /// 而 SwiftUI 的 body 求值没有任何可以插入计时器的入口 ——
    /// 卡在渲染里时靠这个字段至少能定位到「是哪一屏」。
    private var contexts: [String] = []
    private var lastBeat: TimeInterval = 0
    private var stallReported = false
    private var started = false
    private var heartbeatTimer: DispatchSourceTimer?
    private var watchdogTimer: DispatchSourceTimer?

    private let watchdogQueue = DispatchQueue(label: "com.ehviewer.hangprobe", qos: .userInitiated)

    /// 主线程超过这么久没有心跳，判定为卡死
    private let stallThreshold: TimeInterval = 3.0
    /// 单个同步区段超过这么久，记一条慢操作
    private let slowThreshold: TimeInterval = 0.35
    /// 区段栈的最大深度（防止异常嵌套把内存吃光）
    private let maxDepth = 24

    private init() {}

    // MARK: - 启停

    func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lastBeat = now()
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.installHeartbeat()
            LogManager.shared.info("卡顿探针已启动（阈值 \(Int(self?.stallThreshold ?? 3))s）", category: "Hang")
        }
        watchdogQueue.async { [weak self] in
            self?.installWatchdog()
        }
    }

    private func installHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 0.5, leeway: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.lastBeat = self.now()
            self.stallReported = false
            self.lock.unlock()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func installWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let beat = self.lastBeat
            let open = self.stack.map(\.name)
            let ctx = self.contexts.last
            self.lock.unlock()

            let stalled = self.now() - beat
            guard stalled >= self.stallThreshold else { return }

            // 必须用非阻塞获取：主线程若正好卡在 enter/leave 的临界区内，
            // 阻塞式 lock() 会把看门狗线程也挂住，探针就永远不报警了。
            guard self.lock.lock(before: Date()) else { return }
            let already = self.stallReported
            self.stallReported = true
            self.lock.unlock()
            guard !already else { return }

            var parts: [String] = []
            if let ctx { parts.append("屏幕=\(ctx)") }
            parts.append(open.isEmpty
                ? "区段=（无 → 卡在 SwiftUI 渲染 / 系统框架内部）"
                : "区段=" + open.joined(separator: " > "))
            LogManager.shared.error(
                "主线程卡死 \(String(format: "%.1f", stalled))s | " + parts.joined(separator: " | "),
                category: "Hang")
        }
        timer.resume()
        watchdogTimer = timer
    }

    // MARK: - 区段标记

    /// 进入一个同步区段。必须与 `leave()` 成对，且在同一线程上。
    @inline(__always)
    func enter(_ name: String) {
        let t = now()
        lock.lock()
        stack.append(Section(name: name, since: t))
        if stack.count > maxDepth { stack.removeFirst(stack.count - maxDepth) }
        lock.unlock()
    }

    /// 退出最近一个区段；超时则记一条慢操作。
    @inline(__always)
    func leave() {
        let t = now()
        lock.lock()
        guard let last = stack.popLast() else { lock.unlock(); return }
        lock.unlock()

        let elapsed = t - last.since
        guard elapsed >= slowThreshold else { return }
        LogManager.shared.warning(
            "慢操作 \(String(format: "%.2f", elapsed))s @ \(last.name)",
            category: "Hang")
    }

    /// 包一个同步区段，异常路径也会正确出栈。
    @inline(__always)
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        enter(name)
        defer { leave() }
        return body()
    }

    // MARK: - 屏幕上下文

    /// 标记「某屏已出现」。同一屏重复调用只记一次。
    func pushContext(_ name: String) {
        lock.lock()
        if !contexts.contains(name) { contexts.append(name) }
        lock.unlock()
    }

    /// 标记「某屏已离开」。
    func popContext(_ name: String) {
        lock.lock()
        contexts.removeAll { $0 == name }
        lock.unlock()
    }

    // MARK: -

    @inline(__always)
    private func now() -> TimeInterval {
        // 单调时钟：不受系统时间调整影响
        ProcessInfo.processInfo.systemUptime
    }
}

// MARK: - 便捷写法

/// `probe("名称") { ... }` — 只包同步代码，不要跨 await
@inline(__always)
func probe<T>(_ name: String, _ body: () -> T) -> T {
    HangProbe.shared.measure(name, body)
}
