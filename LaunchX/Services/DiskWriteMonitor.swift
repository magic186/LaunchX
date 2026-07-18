import Foundation

/// 磁盘写入监控服务
/// 用于统计和监控应用的磁盘写入量，帮助识别写入过度问题
final class DiskWriteMonitor {
    static let shared = DiskWriteMonitor()

    // MARK: - 统计数据

    private var totalBytesWritten: Int64 = 0
    private var startTime: Date = Date()
    private var lastResetTime: Date = Date()

    // 写入记录（用于计算速率）
    private struct WriteRecord {
        let timestamp: Date
        let bytes: Int64
    }

    private var writeHistory: [WriteRecord] = []
    private let historyLock = NSLock()

    // MARK: - 配置

    private var settings: DiskWriteOptimizationSettings {
        DiskWriteOptimizationSettings.shared
    }

    private var lastUserDefaultsSaveTime: Date = Date.distantPast

    private init() {
        loadStatistics()
    }

    // MARK: - 记录写入

    /// 记录一次磁盘写入
    /// - Parameter bytes: 写入的字节数
    func recordWrite(bytes: Int64) {
        historyLock.lock()
        defer { historyLock.unlock() }

        totalBytesWritten += bytes

        let record = WriteRecord(timestamp: Date(), bytes: bytes)
        writeHistory.append(record)

        // 只保留最近5分钟的记录
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        writeHistory.removeAll { $0.timestamp < fiveMinutesAgo }

        // 定期保存统计数据（每 100 次写入 OR 每 30 秒，降低 I/O 开销）
        if writeHistory.count % 100 == 0
            || Date().timeIntervalSince(lastUserDefaultsSaveTime) >= 30
        {
            lastUserDefaultsSaveTime = Date()
            saveStatistics()
        }

        // 性能日志和警告
        if settings.performanceLoggingEnabled {
            let rate = getCurrentWriteRate()
            if rate > 80 * 1024 {  // 超过 80 KB/s
                print("[DiskWriteMonitor] High write rate: \(formatBytes(Int64(rate)))/s")
            }

            // 超过 100 KB/s 发出严重警告
            if rate > 100 * 1024 {
                print("[DiskWriteMonitor] ⚠️ CRITICAL: Write rate exceeds 100 KB/s: \(formatBytes(Int64(rate)))/s")
                print("[DiskWriteMonitor] Consider enabling all optimizations or investigating the cause")
            }
        }
    }

    // MARK: - 统计查询

    /// 获取当前写入速率（字节/秒）
    func getCurrentWriteRate() -> Double {
        historyLock.lock()
        defer { historyLock.unlock() }

        guard !writeHistory.isEmpty else { return 0 }

        // 计算最近1分钟的写入速率
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        let recentWrites = writeHistory.filter { $0.timestamp >= oneMinuteAgo }

        guard !recentWrites.isEmpty else { return 0 }

        let totalBytes = recentWrites.reduce(0) { $0 + $1.bytes }
        let duration = Date().timeIntervalSince(recentWrites.first!.timestamp)

        guard duration > 0 else { return 0 }

        return Double(totalBytes) / duration
    }

    /// 获取平均写入速率（字节/秒）
    func getAverageWriteRate() -> Double {
        let duration = Date().timeIntervalSince(startTime)
        guard duration > 0 else { return 0 }
        return Double(totalBytesWritten) / duration
    }

    /// 获取总写入量（字节）
    func getTotalBytesWritten() -> Int64 {
        return totalBytesWritten
    }

    /// 获取运行时长（秒）
    func getUptime() -> TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    /// 获取统计摘要
    func getStatistics() -> DiskWriteStatistics {
        let currentRate = getCurrentWriteRate()
        let averageRate = getAverageWriteRate()
        let uptime = getUptime()

        return DiskWriteStatistics(
            totalBytes: totalBytesWritten,
            currentRateBytesPerSecond: currentRate,
            averageRateBytesPerSecond: averageRate,
            uptimeSeconds: uptime,
            startTime: startTime
        )
    }

    // MARK: - 重置

    /// 重置统计数据
    func reset() {
        historyLock.lock()
        defer { historyLock.unlock() }

        totalBytesWritten = 0
        startTime = Date()
        lastResetTime = Date()
        writeHistory.removeAll()

        saveStatistics()
    }

    // MARK: - 持久化

    private func saveStatistics() {
        let data: [String: Any] = [
            "totalBytesWritten": totalBytesWritten,
            "startTime": startTime.timeIntervalSince1970,
            "lastResetTime": lastResetTime.timeIntervalSince1970
        ]
        UserDefaults.standard.set(data, forKey: "diskWriteStatistics")
    }

    private func loadStatistics() {
        guard let data = UserDefaults.standard.dictionary(forKey: "diskWriteStatistics") else {
            return
        }

        if let total = data["totalBytesWritten"] as? Int64 {
            totalBytesWritten = total
        }

        if let startTimestamp = data["startTime"] as? TimeInterval {
            startTime = Date(timeIntervalSince1970: startTimestamp)
        }

        if let resetTimestamp = data["lastResetTime"] as? TimeInterval {
            lastResetTime = Date(timeIntervalSince1970: resetTimestamp)
        }
    }

    // MARK: - 格式化

    /// 格式化字节数为可读字符串
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// 格式化速率为可读字符串
    func formatRate(_ bytesPerSecond: Double) -> String {
        return "\(formatBytes(Int64(bytesPerSecond)))/s"
    }
}

// MARK: - 统计数据结构

struct DiskWriteStatistics {
    let totalBytes: Int64
    let currentRateBytesPerSecond: Double
    let averageRateBytesPerSecond: Double
    let uptimeSeconds: TimeInterval
    let startTime: Date

    var formattedTotalBytes: String {
        DiskWriteMonitor.shared.formatBytes(totalBytes)
    }

    var formattedCurrentRate: String {
        DiskWriteMonitor.shared.formatRate(currentRateBytesPerSecond)
    }

    var formattedAverageRate: String {
        DiskWriteMonitor.shared.formatRate(averageRateBytesPerSecond)
    }

    var formattedUptime: String {
        let hours = Int(uptimeSeconds) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    /// 健康度评分（0-100）
    var healthScore: Int {
        let targetRate: Double = 50 * 1024  // 50 KB/s
        let warningRate: Double = 80 * 1024  // 80 KB/s
        let criticalRate: Double = 100 * 1024  // 100 KB/s

        let rate = averageRateBytesPerSecond

        if rate <= targetRate {
            return 100
        } else if rate <= warningRate {
            // 50-80 KB/s: 100-70分
            let ratio = (rate - targetRate) / (warningRate - targetRate)
            return Int(100 - ratio * 30)
        } else if rate <= criticalRate {
            // 80-100 KB/s: 70-40分
            let ratio = (rate - warningRate) / (criticalRate - warningRate)
            return Int(70 - ratio * 30)
        } else {
            // >100 KB/s: 40-0分
            let ratio = min((rate - criticalRate) / criticalRate, 1.0)
            return Int(40 - ratio * 40)
        }
    }

    /// 健康状态
    var healthStatus: String {
        if healthScore >= 80 {
            return "优秀"
        } else if healthScore >= 60 {
            return "良好"
        } else if healthScore >= 40 {
            return "警告"
        } else {
            return "严重"
        }
    }

    /// 优化建议
    var recommendations: [String] {
        var suggestions: [String] = []

        if currentRateBytesPerSecond > 100 * 1024 {
            suggestions.append("当前写入速率过高，建议检查是否有大量文件变化")
        }

        if averageRateBytesPerSecond > 80 * 1024 {
            suggestions.append("平均写入速率偏高，建议启用所有优化选项")
        }

        if suggestions.isEmpty {
            suggestions.append("写入量正常，继续保持")
        }

        return suggestions
    }
}
