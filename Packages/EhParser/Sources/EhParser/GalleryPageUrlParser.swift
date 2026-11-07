import Foundation

// MARK: - 画廊页面 URL 解析器 (对应 Android GalleryPageUrlParser.java)

public enum GalleryPageUrlParser {

    /// 严格匹配: /s/{pToken}/{gid}-{page}
    private static let strictPattern = try! NSRegularExpression(
        pattern: #"https?://(?:exhentai\.org|e-hentai\.org|lofi\.e-hentai\.org)/s/([0-9a-f]{10})/(\d+)-(\d+)"#
    )

    /// 宽松匹配
    private static let loosePattern = try! NSRegularExpression(
        pattern: #"/s/([0-9a-f]{10})/(\d+)-(\d+)"#
    )

    /// 解析结果
    public struct Result: Sendable {
        public var gid: Int64
        public var pToken: String
        public var page: Int  // 0-based
    }

    /// 严格模式解析
    public static func parse(_ url: String) -> Result? {
        let range = NSRange(url.startIndex..., in: url)
        if let match = strictPattern.firstMatch(in: url, range: range),
           let pTokenRange = Range(match.range(at: 1), in: url),
           let gidRange = Range(match.range(at: 2), in: url),
           let pageRange = Range(match.range(at: 3), in: url),
           let gid = Int64(url[gidRange]),
           let page = Int(url[pageRange]) {
            return Result(gid: gid, pToken: String(url[pTokenRange]), page: page - 1) // 转为 0-based
        }
        return nil
    }

    /// 宽松模式解析
    public static func parseLoose(_ url: String) -> Result? {
        if let r = parse(url) { return r }

        let range = NSRange(url.startIndex..., in: url)
        if let match = loosePattern.firstMatch(in: url, range: range),
           let pTokenRange = Range(match.range(at: 1), in: url),
           let gidRange = Range(match.range(at: 2), in: url),
           let pageRange = Range(match.range(at: 3), in: url),
           let gid = Int64(url[gidRange]),
           let page = Int(url[pageRange]) {
            return Result(gid: gid, pToken: String(url[pTokenRange]), page: page - 1)
        }
        return nil
    }
}
