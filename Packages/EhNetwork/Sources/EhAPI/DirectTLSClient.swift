import Foundation
import Network
import Security

// MARK: - 直连通道（等价于 Android OkHttp 的 Dns 接口）
//
// 为什么需要这么一个东西：
//
//   URLSession 没有任何 DNS 钩子。想把域名换成 IP，只能把 URL 的 host 改成 IP，
//   而 CFNetwork 对 IP 字面量**不发 SNI**（RFC 6066 禁止 SNI 里放 IP），于是：
//     · Cloudflare 前置的站点（e-hentai.org / forums.e-hentai.org）
//       会在 ClientHello 阶段直接被拒绝握手，连证书都拿不到；
//     · 单源服务器（eght.org）虽然会返回默认证书，但校验用的是 IP，必然不匹配。
//   实测过同一台机器、同一个端口：
//     104.20.18.168 带 SNI e-hentai.org   → 连接被重置
//     104.20.18.168 不带 SNI              → SSLV3_ALERT_HANDSHAKE_FAILURE
//     104.20.18.168 带 SNI cloudflare.com → 握手成功（证明 IP 是活的）
//   所以「改 URL 为 IP」这条路在 iOS 上是结构性走不通的，不是表过期的问题。
//
//   Network.framework 把两件事拆开了：
//     端点（NWEndpoint）  = 连到哪个地址（IP）
//     TLS SNI             = 握手时报哪个名字（原域名）
//   这正是 OkHttp `Dns` 接口的行为 —— 只换地址，不动身份。
//
// 代价是要自己讲 HTTP/1.1，因此这里只实现回退路径需要的最小子集：
//   · 单次请求、Connection: close、不跟随重定向
//   · 支持 Content-Length 与 chunked（漫画站的 JSON / HTML 都是这两种）
//   · 剥掉 Accept-Encoding，让服务端回明文，省掉解压
//   · 手动带 Cookie（URL 变成 IP 后 HTTPCookieStorage 不会自动匹配）
//
// 只在「主请求已经失败」的回退里使用，正常路径仍然走 URLSession。

/// 用 NWConnection 自建的一条 HTTPS 直连通道。
final class DirectTLSClient: @unchecked Sendable {
    static let shared = DirectTLSClient()

    private init() {}

    /// 单次响应上限，防止异常响应把内存吃满
    private static let maxResponseBytes = 48 * 1024 * 1024

    enum ClientError: LocalizedError, Equatable {
        case invalidRequest
        case connectFailed
        case readFailed
        case malformedResponse
        case responseTooLarge
        case tlsRejected

        var errorDescription: String? {
            switch self {
            case .invalidRequest:    return "无法构造直连请求"
            case .connectFailed:     return "直连连接失败"
            case .readFailed:        return "直连读取失败"
            case .malformedResponse: return "直连响应格式异常"
            case .responseTooLarge:  return "直连响应超出大小上限"
            case .tlsRejected:       return "直连 TLS 握手被拒"
            }
        }
    }

    /// 这类失败换一个 IP 也没用，调用方可以直接放弃后续候选
    static func isFatal(_ error: Error) -> Bool {
        if let clientError = error as? ClientError {
            return clientError == .tlsRejected || clientError == .malformedResponse
        }
        if let nwError = error as? NWError, case .tls = nwError {
            return true
        }
        return false
    }

    /// 对 `ip:port` 发起 TLS（SNI = host），完成一次 HTTP/1.1 往返。
    func perform(
        _ request: URLRequest,
        ip: String,
        host: String,
        timeout: TimeInterval = 10
    ) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw ClientError.invalidRequest }

        let connection = makeConnection(ip: ip, host: host, port: url.port ?? 443)

        // 总超时：到点直接 cancel，正在等待的 receive 会以错误返回。
        // 用 ConnectionBox 包一层是因为 Task 的闭包是 @Sendable，
        // 直接捕获 NWConnection 在严格并发模式下可能过不了检查。
        let box = ConnectionBox(connection)
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if !Task.isCancelled { box.connection.cancel() }
        }
        defer { watchdog.cancel() }

        do {
            try await waitUntilReady(connection)
            try await send(connection, buildRequestData(request, host: host))

            var buffer = Data()
            while true {
                let (chunk, isComplete) = try await receiveChunk(connection)
                if !chunk.isEmpty {
                    buffer.append(chunk)
                    if buffer.count > Self.maxResponseBytes {
                        connection.cancel()
                        throw ClientError.responseTooLarge
                    }
                }
                if let parsed = HTTP1ResponseParser.parse(buffer, url: url, connectionClosed: isComplete) {
                    connection.cancel()
                    return parsed
                }
                if isComplete {
                    connection.cancel()
                    throw ClientError.malformedResponse
                }
            }
        } catch {
            // 任何一条失败路径都要把连接收掉，否则会留下一个还在跑的 socket
            connection.cancel()
            throw error
        }
    }

    // MARK: - 连接

    private func makeConnection(ip: String, host: String, port: Int) -> NWConnection {
        let tls = NWProtocolTLS.Options()

        // ★ 关键的一行：握手时报原域名，而不是 IP。
        //   有了它，Cloudflare 才会返回 e-hentai.org 的证书。
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, host)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        // 端点写的是 IP，URL 里没有域名可供系统校验，所以这里显式按原域名评估。
        // 一旦设置了 verify block，系统的默认校验就不再执行，必须自己做完。
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, secTrust, complete in
                let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
                let policy = SecPolicyCreateSSL(true, host as CFString)
                SecTrustSetPolicies(trust, policy)
                var error: CFError?
                complete(SecTrustEvaluateWithError(trust, &error))
            },
            DispatchQueue.global(qos: .userInitiated)
        )

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        tcp.noDelay = true

        let parameters = NWParameters(tls: tls, tcp: tcp)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? .https
        return NWConnection(host: NWEndpoint.Host(ip), port: endpointPort, using: parameters)
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = OnceGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.run { continuation.resume() }
                case .failed(let error):
                    gate.run { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.run { continuation.resume(throwing: ClientError.connectFailed) }
                case .waiting(let error):
                    // 没有可用路由等情况：直接失败，交给上层换 IP 或放弃
                    gate.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receiveChunk(_ connection: NWConnection) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (data ?? Data(), isComplete))
            }
        }
    }

    // MARK: - 请求编码

    private func buildRequestData(_ request: URLRequest, host: String) -> Data {
        guard let url = request.url else { return Data() }

        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { path += "?" + query }

        // 这几个头由本通道自己决定，原样带过去会打架
        let banned: Set<String> = [
            "host", "connection", "accept-encoding", "content-length", "transfer-encoding",
        ]

        var lines: [(String, String)] = [("Host", host)]
        if let fields = request.allHTTPHeaderFields {
            for (key, value) in fields where !banned.contains(key.lowercased()) {
                lines.append((key, value))
            }
        }

        // URL 的 host 变成 IP 后，HTTPCookieStorage 不会自动匹配，手动带上
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in fields { lines.append((key, value)) }
        }

        if let body = request.httpBody, !body.isEmpty {
            lines.append(("Content-Length", String(body.count)))
        }
        // 明确要求短连接：解析时就能以「连接关闭」作为无长度响应的终止条件
        lines.append(("Connection", "close"))

        var head = "\(request.httpMethod ?? "GET") \(path) HTTP/1.1\r\n"
        for (key, value) in lines {
            head += "\(key): \(value)\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        if let body = request.httpBody, !body.isEmpty { data.append(body) }
        return data
    }
}

// MARK: - 保证 continuation 只恢复一次

/// 让 NWConnection 能安全地被 @Sendable 闭包捕获
private final class ConnectionBox: @unchecked Sendable {
    let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }
}

/// `NWConnection` 的状态回调可能触发多次（ready 之后还会有 cancelled / failed），
/// 而 continuation 被恢复两次会直接 crash。用它兜住。
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func run(_ body: () -> Void) {
        lock.lock()
        if used {
            lock.unlock()
            return
        }
        used = true
        lock.unlock()
        body()
    }
}

// MARK: - HTTP/1.1 响应解析

private enum HTTP1ResponseParser {

    /// 数据还不够时返回 nil；足够解析出完整响应时返回结果。
    /// `connectionClosed` 为真表示对端已经关闭，此时对「没有长度信息」的响应
    /// 以「收到多少算多少」收尾。
    static func parse(
        _ data: Data,
        url: URL,
        connectionClosed: Bool
    ) -> (Data, URLResponse)? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[data.startIndex..<headerEnd.lowerBound],
                                      encoding: .utf8) else { return nil }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        // 状态行: HTTP/1.1 200 OK
        let statusLine = lines.removeFirst()
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let status = Int(parts[1]) else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { headers[key] = value }
        }

        // 用不区分大小写的副本做查找（注意不能用 uniqueKeysWithValues：
        // Set-Cookie 会出现重复键，那样会直接 crash）
        var lower: [String: String] = [:]
        for (key, value) in headers { lower[key.lowercased()] = value }

        let body = data[headerEnd.upperBound...]
        var finalBody: Data?

        if status == 204 || status == 304 {
            // 这两个状态码按规范没有正文；不等长度/关闭，直接收尾，
            // 否则会一直等到超时。
            finalBody = Data()
        } else if let encoding = lower["transfer-encoding"], encoding.lowercased().contains("chunked") {
            let decoded = decodeChunked(body)
            if decoded.complete {
                finalBody = decoded.data
            } else if connectionClosed {
                finalBody = decoded.data
            }
        } else if let lengthText = lower["content-length"], let expected = Int(lengthText) {
            if body.count >= expected {
                finalBody = Data(body.prefix(expected))
            } else if connectionClosed {
                finalBody = Data(body)
            }
        } else {
            // 既没有 Content-Length 也没有 chunked：只能等连接关闭
            finalBody = connectionClosed ? Data(body) : nil
        }

        guard let bodyData = finalBody,
              let response = HTTPURLResponse(url: url,
                                             statusCode: status,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: headers)
        else { return nil }

        return (bodyData, response)
    }

    /// 解析 chunked 正文。返回已解出的部分，以及是否已经读到终止块。
    private static func decodeChunked(_ body: Data) -> (data: Data, complete: Bool) {
        var result = Data()
        var index = body.startIndex

        while true {
            guard let lineEnd = body[index...].range(of: Data("\r\n".utf8)) else {
                return (result, false)
            }
            let sizeText = String(data: body[index..<lineEnd.lowerBound], encoding: .utf8) ?? ""
            let hex = sizeText.split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(hex.trimmingCharacters(in: .whitespaces), radix: 16) else {
                return (result, false)
            }
            index = lineEnd.upperBound

            if size == 0 {
                return (result, true)
            }

            let consumed = body.distance(from: body.startIndex, to: index)
            guard body.count - consumed >= size + 2 else {
                return (result, false)
            }

            let chunkEnd = body.index(index, offsetBy: size)
            result.append(body[index..<chunkEnd])
            index = body.index(chunkEnd, offsetBy: 2)
        }
    }
}
