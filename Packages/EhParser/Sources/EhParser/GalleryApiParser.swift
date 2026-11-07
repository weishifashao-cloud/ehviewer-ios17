import Foundation
import EhModels

// MARK: - GalleryApiParser (对应 Android GalleryApiParser.java)
// 解析 gdata JSON API 响应，批量填充 GalleryInfo 字段

public enum GalleryApiParser {

    /// 解析 gdata API 响应并更新画廊列表
    /// - Parameters:
    ///   - data: JSON 响应 data
    ///   - galleries: 需要填充的画廊列表 (inout)
    public static func parse(_ data: Data, galleries: inout [GalleryInfo]) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gmetadata = json["gmetadata"] as? [[String: Any]]
        else {
            // 检查是否有 error
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw EhParseError.parseFailure(error)
            }
            throw EhParseError.parseFailure("Failed to parse gdata response")
        }

        for item in gmetadata {
            guard let gid = item["gid"] as? Int64 ?? (item["gid"] as? Int).map({ Int64($0) }) else {
                continue
            }

            // 在 galleries 中找到对应的 GalleryInfo 并更新
            guard let idx = galleries.firstIndex(where: { $0.gid == gid }) else {
                continue
            }

            // token
            if let token = item["token"] as? String {
                galleries[idx].token = token
            }

            // title / title_jpn
            if let title = item["title"] as? String, !title.isEmpty {
                galleries[idx].title = title
            }
            if let titleJpn = item["title_jpn"] as? String, !titleJpn.isEmpty {
                galleries[idx].titleJpn = titleJpn
            }

            // thumb
            if let thumb = item["thumb"] as? String {
                galleries[idx].thumb = thumb
            }

            // category
            if let category = item["category"] as? String {
                galleries[idx].category = EhCategory.from(string: category)
            }

            // posted (Unix timestamp string → 格式化日期)
            if let posted = item["posted"] as? String {
                galleries[idx].posted = posted
            }

            // uploader
            if let uploader = item["uploader"] as? String {
                galleries[idx].uploader = uploader
            }

            // rating (string → Float)
            if let ratingStr = item["rating"] as? String, let rating = Float(ratingStr) {
                galleries[idx].rating = rating
            }

            // filecount → pages
            if let filecount = item["filecount"] as? String, let pages = Int(filecount) {
                galleries[idx].pages = pages
            }

            // tags → simpleTags + simpleLanguage
            if let tags = item["tags"] as? [String] {
                galleries[idx].simpleTags = tags
                galleries[idx].simpleLanguage = generateSLang(from: tags)
            }

            // thumb_width / thumb_height (可选)
            if let tw = item["thumb_width"] as? Int {
                galleries[idx].thumbWidth = tw
            }
            if let th = item["thumb_height"] as? Int {
                galleries[idx].thumbHeight = th
            }
        }
    }

    // MARK: - 从标签推断语言 (对应 Android GalleryInfo.generateSLang)

    /// 简体语言表 (对应 Android S_LANG_TAGS → S_LANGS)
    private static let langTagMap: [(tag: String, lang: String)] = [
        ("language:chinese", "ZH"),
        ("language:english", "EN"),
        ("language:japanese", "JA"),
        ("language:korean", "KO"),
        ("language:french", "FR"),
        ("language:german", "DE"),
        ("language:spanish", "ES"),
        ("language:italian", "IT"),
        ("language:russian", "RU"),
        ("language:thai", "TH"),
        ("language:portuguese", "PT"),
        ("language:polish", "PL"),
        ("language:dutch", "NL"),
        ("language:hungarian", "HU"),
        ("language:vietnamese", "VI"),
        ("language:czech", "CS"),
        ("language:indonesian", "ID"),
        ("language:arabic", "AR"),
        ("language:turkish", "TR"),
    ]

    public static func generateSLang(from tags: [String]) -> String? {
        for (tag, lang) in langTagMap {
            if tags.contains(tag) {
                return lang
            }
        }
        return nil
    }
}
