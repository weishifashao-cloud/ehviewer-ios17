import Foundation

// MARK: - 登录响应解析 (对应 Android SignInParser.java)

public enum SignInParser {

    /// 用户名匹配正则
    private static let namePattern = try! NSRegularExpression(
        pattern: #"<p>You are now logged in as: (.+?)<"#
    )

    /// 错误信息匹配正则 (两种格式)
    private static let errorPattern = try! NSRegularExpression(
        pattern: #"(?:<h4>The error returned was:</h4>\s*<p>(.+?)</p>)|(?:<span class="postcolor">(.+?)</span>)"#
    )

    /// 解析登录响应 HTML
    /// - Returns: 登录成功时返回用户名
    /// - Throws: 登录失败时抛出 `EhParseError`
    public static func parse(_ body: String) throws -> String {
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)

        // 检查是否成功登录
        if let match = namePattern.firstMatch(in: body, range: fullRange),
           let nameRange = Range(match.range(at: 1), in: body) {
            return String(body[nameRange])
        }

        // 检查是否有错误信息
        if let match = errorPattern.firstMatch(in: body, range: fullRange) {
            // group(1) 或 group(2)
            if let range1 = Range(match.range(at: 1), in: body) {
                throw EhParseError.signInError(String(body[range1]))
            }
            if let range2 = Range(match.range(at: 2), in: body) {
                throw EhParseError.signInError(String(body[range2]))
            }
        }

        throw EhParseError.parseFailure("Can't parse sign in")
    }
}

// MARK: - 解析错误类型 (用于 Parser 层的通用错误)

public enum EhParseError: LocalizedError, Sendable {
    case parseFailure(String)
    case signInError(String)

    public var errorDescription: String? {
        switch self {
        case .parseFailure(let msg): return "Parse error: \(msg)"
        case .signInError(let msg): return msg
        }
    }
}
