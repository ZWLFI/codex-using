import Foundation

enum CodexClientError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}

enum CodexLocator {
    static var candidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]
    }

    static func resolve() throws -> String {
        guard let path = candidates.first(where: FileManager.default.isExecutableFile) else {
            throw CodexClientError.message("未找到 Codex，已检查应用和常用命令路径")
        }
        return path
    }
}

private struct RPCErrorBody: Decodable {
    let code: Int?
    let message: String
}

private struct RPCResponse<Result: Decodable>: Decodable {
    let result: Result?
    let error: RPCErrorBody?
}

private struct InitializeResult: Decodable {
    let userAgent: String?
}

actor CodexAppServerClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: Pipe?
    private var buffer = Data()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 1
    private var ready = false
    private var resolvedPath: String?
    private var rateLimitChangeHandler: (@Sendable () -> Void)?

    func setRateLimitChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        rateLimitChangeHandler = handler
    }

    func executablePath() -> String? { resolvedPath ?? (try? CodexLocator.resolve()) }

    func fetch() async throws -> (RateLimitsResult, UsageResult, String) {
        try await connect()
        async let rateLimits: RateLimitsResult = request("account/rateLimits/read")
        async let usage: UsageResult = request("account/usage/read")
        return try await (rateLimits, usage, resolvedPath ?? "")
    }

    func stop() {
        let process = process
        reset(error: CodexClientError.message("Codex App Server 已停止"))
        if process?.isRunning == true { process?.terminate() }
    }

    private func connect() async throws {
        if ready, process?.isRunning == true { return }
        if process != nil { stop() }

        let path = try CodexLocator.resolve()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server", "--stdio", "--config", "features.plugins=false"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:" +
            (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consume(data) }
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.terminated(status: process.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw CodexClientError.message("无法启动 Codex：\(error.localizedDescription)")
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = outputPipe
        resolvedPath = path

        do {
            let _: InitializeResult = try await request(
                "initialize",
                params: ["clientInfo": ["name": "gpt-quota-menu", "version": "2.2.0"]]
            )
            try sendNotification("initialized")
            ready = true
        } catch {
            stop()
            throw error
        }
    }

    private func request<Result: Decodable>(
        _ method: String,
        params: [String: Any]? = nil,
        timeout: TimeInterval = 20
    ) async throws -> Result {
        let data = try await rawRequest(method, params: params, timeout: timeout)
        let response: RPCResponse<Result>
        do {
            response = try JSONDecoder().decode(RPCResponse<Result>.self, from: data)
        } catch {
            throw CodexClientError.message("Codex 响应格式已变更：\(error.localizedDescription)")
        }
        if let error = response.error {
            throw CodexClientError.message(error.message)
        }
        guard let result = response.result else {
            throw CodexClientError.message("Codex 返回了空结果")
        }
        return result
    }

    private func rawRequest(
        _ method: String,
        params: [String: Any]?,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let input else { throw CodexClientError.message("Codex App Server 未连接") }
        let id = nextID
        nextID += 1
        var object: [String: Any] = ["id": id, "method": method]
        if let params { object["params"] = params }

        var payload = try JSONSerialization.data(withJSONObject: object)
        payload.append(10)

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try input.write(contentsOf: payload)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
                return
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.timeout(id: id)
            }
        }
    }

    private func sendNotification(_ method: String) throws {
        guard let input else { throw CodexClientError.message("Codex App Server 未连接") }
        var payload = try JSONSerialization.data(withJSONObject: ["method": method])
        payload.append(10)
        try input.write(contentsOf: payload)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if let id = (object["id"] as? NSNumber)?.intValue,
           let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: line)
            return
        }
        if object["method"] as? String == "account/rateLimits/updated" {
            rateLimitChangeHandler?()
        }
    }

    private func timeout(id: Int) {
        pending.removeValue(forKey: id)?.resume(
            throwing: CodexClientError.message("读取 Codex 数据超时")
        )
    }

    private func terminated(status: Int32) {
        guard process != nil else { return }
        reset(error: CodexClientError.message("Codex App Server 已退出（\(status)）"))
    }

    private func reset(error: Error) {
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
        input = nil
        output = nil
        buffer.removeAll(keepingCapacity: true)
        ready = false
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }
}

