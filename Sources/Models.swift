import Foundation

struct QuotaWindow: Equatable {
    let title: String
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, 100 - usedPercent))
    }

    var resetText: String {
        guard let resetsAt else {
            return "重置时间未知"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = resetDateFormat
        return "重置 " + formatter.string(from: resetsAt)
    }

    private var resetDateFormat: String {
        if let windowDurationMins, windowDurationMins >= 24 * 60 {
            return "M月d日"
        }

        return "HH:mm"
    }
}

struct QuotaSnapshot: Equatable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let limitName: String
    let planType: String?
    let updatedAt: Date

    static let empty = QuotaSnapshot(
        primary: nil,
        secondary: nil,
        limitName: "Codex",
        planType: nil,
        updatedAt: Date()
    )
}

enum QuotaFetchError: Error, LocalizedError {
    case codexBinaryMissing(String)
    case serverExited(String)
    case malformedResponse
    case missingRateLimits
    case rpcError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .codexBinaryMissing(let path):
            return "找不到 Codex 二进制：" + path
        case .serverExited(let detail):
            return "Codex app-server 已退出：" + detail
        case .malformedResponse:
            return "app-server 返回格式无法解析"
        case .missingRateLimits:
            return "app-server 没有返回额度数据"
        case .rpcError(let message):
            return "app-server 错误：" + message
        case .timeout:
            return "读取额度超时"
        }
    }
}
