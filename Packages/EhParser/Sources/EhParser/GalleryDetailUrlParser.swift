import Foundation

// MARK: - 画廊详情 URL 解析器 (对应 Android GalleryDetailUrlParser.java)

public enum GalleryDetailUrlParser {

    /// 严格匹配: 完整 URL
    private static let strictPattern = try! NSRegularExpression(
        pattern: #"https?://(?:exhentai\.org|e-hentai\.org|lofi\.e-hentai\.org)/(?:g|mpv)/(\d+)/([0-9a-f]{10})"#
    )

    /// 宽松匹配: 仅 gid/token
    private static let loosePattern = try! NSRegularExpression(
        pattern: #"(\d+)/([0-9a-f]{10})"#
    )

    /// 解析结果
    public struct Result: Sendable {
        public var gid: Int64
        public var token: String
    }

    /// 严格模式解析 (对应 Android parse, strict=true)
    public static func parse(_ url: String) -> Result? {
        let range = NSRange(url.startIndex..., in: url)
        if let match = strictPattern.firstMatch(in: url, range: range),
           let gidRange = Range(match.range(at: 1), in: url),
           let tokenRange = Range(match.range(at: 2), in: url),
           let gid = Int64(url[gidRange]) {
            return Result(gid: gid, token: String(url[tokenRange]))
        }
        return nil
    }

    /// 宽松模式解析 (对应 Android parse, strict=false)
    public static func parseLoose(_ url: String) -> Result? {
        // 先尝试严格模式
        if let r = parse(url) { return r }

        // 宽松匹配
        let range = NSRange(url.startIndex..., in: url)
        if let match = loosePattern.firstMatch(in: url, range: range),
           let gidRange = Range(match.range(at: 1), in: url),
           let tokenRange = Range(match.range(at: 2), in: url),
           let gid = Int64(url[gidRange]) {
            return Result(gid: gid, token: String(url[tokenRange]))
        }
        return nil
    }
}
