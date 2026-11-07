import Foundation

// MARK: - 画廊列表 URL 解析器 (对应 Android GalleryListUrlParser.java)

public enum GalleryListUrlParser {

    /// 从画廊列表 URL 推断搜索模式、关键词等
    public struct Result: Sendable {
        public var mode: Int  // ListUrlBuilder.MODE_*
        public var category: Int
        public var keyword: String?
    }

    /// 上传者模式正则: /uploader/{name}
    private static let uploaderPattern = try! NSRegularExpression(
        pattern: #"/uploader/(.+?)(?:\?|$)"#
    )

    /// 标签模式正则: /tag/{tag}
    private static let tagPattern = try! NSRegularExpression(
        pattern: #"/tag/(.+?)(?:\?|$)"#
    )

    /// 解析 URL 以推断搜索相关参数
    public static func parse(_ url: String) -> Result? {
        guard let comp = URLComponents(string: url) else { return nil }

        let path = comp.path

        // Uploader 模式
        let nsPath = path as NSString
        let pathRange = NSRange(location: 0, length: nsPath.length)
        if let match = uploaderPattern.firstMatch(in: path, range: pathRange),
           let nameRange = Range(match.range(at: 1), in: path) {
            let uploader = String(path[nameRange]).removingPercentEncoding ?? String(path[nameRange])
            return Result(mode: 1, category: 0, keyword: uploader) // MODE_UPLOADER
        }

        // Tag 模式
        if let match = tagPattern.firstMatch(in: path, range: pathRange),
           let tagRange = Range(match.range(at: 1), in: path) {
            let tag = String(path[tagRange]).removingPercentEncoding ?? String(path[tagRange])
            return Result(mode: 2, category: 0, keyword: tag) // MODE_TAG
        }

        // Popular 模式
        if path.contains("popular") {
            return Result(mode: 3, category: 0, keyword: nil) // MODE_WHATS_HOT
        }

        // Watched 模式
        if path.contains("watched") {
            return Result(mode: 5, category: 0, keyword: nil) // MODE_SUBSCRIPTION
        }

        // TopList 模式
        if path.contains("toplist") {
            return Result(mode: 7, category: 0, keyword: nil) // MODE_TOP_LIST
        }

        // Favorites 模式
        if path.contains("favorites") {
            return nil // 收藏有独立的 FavListUrlBuilder
        }

        // 普通搜索模式
        let queryItems = comp.queryItems ?? []
        let keyword = queryItems.first(where: { $0.name == "f_search" })?.value
        let catValue = queryItems.first(where: { $0.name == "f_cats" })?.value
        let category = catValue.flatMap { Int($0) } ?? 0

        return Result(mode: 0, category: category, keyword: keyword) // MODE_NORMAL
    }
}
