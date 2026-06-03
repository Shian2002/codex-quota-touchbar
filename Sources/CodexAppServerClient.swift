import Foundation

final class CodexAppServerClient {
    private let codexPath: String
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var nextID = 1
    private let decoder = JSONDecoder()

    init(codexPath: String = "/Applications/Codex.app/Contents/Resources/codex") {
        self.codexPath = codexPath
    }

    deinit {
        stop()
    }

    func readRateLimits() throws -> QuotaSnapshot {
        try ensureStarted()
        _ = try request(method: "initialize", params: [
            "clientInfo": [
                "name": "codex-quota-touchbar",
                "title": "Codex Quota Touch Bar",
                "version": "0.1.0"
            ],
            "capabilities": [
                "experimentalApi": true,
                "requestAttestation": false,
                "optOutNotificationMethods": []
            ]
        ])

        let response = try request(method: "account/rateLimits/read", params: NSNull())
        guard let result = response["result"] as? [String: Any] else {
            throw QuotaFetchError.malformedResponse
        }

        let selectedLimits = selectRateLimits(from: result)
        guard let rateLimits = selectedLimits else {
            throw QuotaFetchError.missingRateLimits
        }

        let limitName = (rateLimits["limitName"] as? String)
            ?? (rateLimits["limitId"] as? String)
            ?? "Codex"
        let planType = rateLimits["planType"] as? String

        return QuotaSnapshot(
            primary: parseWindow(rateLimits["primary"], fallbackTitle: "5小时"),
            secondary: parseWindow(rateLimits["secondary"], fallbackTitle: "周额度"),
            limitName: limitName,
            planType: planType,
            updatedAt: Date()
        )
    }

    func stop() {
        process?.terminate()
        process = nil
        input = nil
        output = nil
    }

    private func ensureStarted() throws {
        if let process, process.isRunning {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw QuotaFetchError.codexBinaryMissing(codexPath)
        }

        let newProcess = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        newProcess.executableURL = URL(fileURLWithPath: codexPath)
        newProcess.arguments = ["app-server", "--listen", "stdio://"]
        newProcess.standardInput = stdinPipe
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe

        try newProcess.run()
        process = newProcess
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
    }

    private func request(method: String, params: Any) throws -> [String: Any] {
        guard let process, process.isRunning, let input, let output else {
            throw QuotaFetchError.serverExited("进程未运行")
        }

        let id = nextID
        nextID += 1
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard var line = String(data: data, encoding: .utf8) else {
            throw QuotaFetchError.malformedResponse
        }
        line += "\n"
        input.write(Data(line.utf8))

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            guard let responseLine = try readLine(from: output) else {
                if !process.isRunning {
                    throw QuotaFetchError.serverExited("没有更多输出")
                }
                continue
            }

            guard
                let responseData = responseLine.data(using: .utf8),
                let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
            else {
                continue
            }

            if let responseID = object["id"] as? Int, responseID == id {
                if let error = object["error"] as? [String: Any] {
                    throw QuotaFetchError.rpcError((error["message"] as? String) ?? "未知错误")
                }
                return object
            }
        }

        throw QuotaFetchError.timeout
    }

    private func readLine(from handle: FileHandle) throws -> String? {
        var data = Data()
        while true {
            let byte = try handle.read(upToCount: 1)
            guard let byte, !byte.isEmpty else {
                return data.isEmpty ? nil : String(data: data, encoding: .utf8)
            }
            if byte[0] == 10 {
                return String(data: data, encoding: .utf8)
            }
            data.append(byte)
        }
    }

    private func selectRateLimits(from result: [String: Any]) -> [String: Any]? {
        if
            let byID = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = byID["codex"] as? [String: Any] {
            return codex
        }

        return result["rateLimits"] as? [String: Any]
    }

    private func parseWindow(_ value: Any?, fallbackTitle: String) -> QuotaWindow? {
        guard let object = value as? [String: Any] else {
            return nil
        }

        let usedPercent = object["usedPercent"] as? Int ?? 0
        let duration = object["windowDurationMins"] as? Int
        let resetsAtSeconds = object["resetsAt"] as? TimeInterval
        let resetsAt = resetsAtSeconds.map { Date(timeIntervalSince1970: $0) }

        let title: String
        if let duration {
            if duration == 300 {
                title = "5小时"
            } else if duration >= 10080 {
                title = "周额度"
            } else if duration >= 60 {
                title = "\(duration / 60)小时"
            } else {
                title = "\(duration)分钟"
            }
        } else {
            title = fallbackTitle
        }

        return QuotaWindow(
            title: title,
            usedPercent: usedPercent,
            windowDurationMins: duration,
            resetsAt: resetsAt
        )
    }
}

