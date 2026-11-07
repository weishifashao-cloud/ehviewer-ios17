import Foundation
import EhModels
import SwiftSoup

// MARK: - 主页配额解析器 (对应 Android EhHomeParser.java)

public enum HomeParser {

    // MARK: 正则 — 图片配额 (新旧两种格式)

    private static let imageLimitNewRegex = try! NSRegularExpression(
        pattern: #"<p>You are currently at <strong>(.+?)</strong> towards your account limit of <strong>(.+?)</strong>.</p>\n<p>You can reset your image quota by spending <strong>(.+?)</strong> GP.</p>"#,
        options: .dotMatchesLineSeparators
    )

    private static let imageLimitOldRegex = try! NSRegularExpression(
        pattern: #"<p>You are currently at <strong>(\d+)</strong> towards a limit of <strong>(\d+)</strong>.</p>.+?<p>Reset Cost: <strong>(\d+)</strong> GP</p>"#,
        options: .dotMatchesLineSeparators
    )

    // MARK: - 解析 (对应 Android EhHomeParser.parse)

    public static func parse(_ body: String) -> HomeDetail {
        var detail = HomeDetail()

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)

        // 先尝试新格式，再尝试旧格式
        let match: NSTextCheckingResult?
        if let m = imageLimitNewRegex.firstMatch(in: body, range: fullRange) {
            match = m
        } else {
            match = imageLimitOldRegex.firstMatch(in: body, range: fullRange)
        }

        if let match = match {
            let usedStr = extractGroupClean(match: match, group: 1, in: body)
            let totalStr = extractGroupClean(match: match, group: 2, in: body)
            let costStr = extractGroupClean(match: match, group: 3, in: body)

            detail.currentUsed = Int(usedStr) ?? 0
            detail.totalLimit = Int(totalStr) ?? 0
            detail.resetCost = Int(costStr) ?? 0
        }

        return detail
    }

    /// 提取正则分组并去除逗号 (对应 Android getGroupIntString)
    private static func extractGroupClean(match: NSTextCheckingResult, group: Int, in body: String) -> String {
        guard let range = Range(match.range(at: group), in: body) else { return "0" }
        return String(body[range]).replacingOccurrences(of: ",", with: "")
    }
}
