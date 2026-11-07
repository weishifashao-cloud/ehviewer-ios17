import Foundation
import SwiftSoup

// MARK: - 论坛页面解析器 (对应 Android ForumsParser.java)

public enum ForumsParser {

    /// 从论坛首页 HTML 提取用户个人资料 URL
    /// 对应 Android ForumsParser.parse: d.getElementById("userlinks").child(0).child(0).child(0).attr("href")
    public static func parseProfileUrl(_ body: String) throws -> String {
        let doc = try SwiftSoup.parse(body, "https://forums.e-hentai.org/")
        guard let userlinks = try doc.getElementById("userlinks") else {
            throw ParserError.missingElement("#userlinks")
        }
        let href = try userlinks.child(0).child(0).child(0).attr("href")
        guard !href.isEmpty else {
            throw ParserError.missingElement("profile href")
        }
        return href
    }
}

// MARK: - 解析错误

public enum ParserError: LocalizedError, Sendable {
    case missingElement(String)

    public var errorDescription: String? {
        switch self {
        case .missingElement(let sel): return "Missing element: \(sel)"
        }
    }
}
