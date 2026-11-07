import Foundation
import SwiftSoup
import EhModels

// MARK: - GalleryPageParser (对应 Android GalleryPageParser.java)
// 解析单个画廊图片页面 → 图片 URL + showKey

public enum GalleryPageParser {

    /// 图片 URL 正则 (对应 Android PATTERN_IMAGE_URL)
    private static let imageUrlRegex = try! NSRegularExpression(
        pattern: #"<img[^>]+id="img"[^>]+src="([^"]+)"[^>]*>"#
    )

    /// showKey 正则 (对应 Android PATTERN_SHOW_KEY)
    private static let showKeyRegex = try! NSRegularExpression(
        pattern: #"var\s+showkey\s*=\s*"([^"]+)""#
    )

    /// skipHathKey 正则
    private static let skipHathKeyRegex = try! NSRegularExpression(
        pattern: #"onclick="return nl\('([^']+)'\)"#
    )

    /// 原图链接正则
    private static let originUrlRegex = try! NSRegularExpression(
        pattern: #"<a[^>]+href="([^"]+)"[^>]*>Download original"#
    )

    // MARK: - XML 反转义 (对应 Android StringUtils.unescapeXml)
    static func unescapeXml(_ string: String) -> String {
        string.replacingOccurrences(of: "&amp;", with: "&")
              .replacingOccurrences(of: "&lt;", with: "<")
              .replacingOccurrences(of: "&gt;", with: ">")
              .replacingOccurrences(of: "&quot;", with: "\"")
              .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// 解析图片页面 HTML
    public static func parse(_ html: String) throws -> GalleryPageResult {
        var result = GalleryPageResult()

        let fullRange = NSRange(html.startIndex..., in: html)

        // 图片 URL (apply unescapeXml — HTML attributes may contain &amp; etc.)
        if let match = imageUrlRegex.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            result.imageUrl = unescapeXml(String(html[range]))
        } else {
            throw GalleryPageParser.Error.imageUrlNotFound
        }

        // showKey
        if let match = showKeyRegex.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            result.showKey = String(html[range])
        }

        // skipHathKey (nl key)
        if let match = skipHathKeyRegex.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            result.skipHathKey = unescapeXml(String(html[range]))
        }

        // 原图 URL
        if let match = originUrlRegex.firstMatch(in: html, range: fullRange),
           let range = Range(match.range(at: 1), in: html) {
            result.originImageUrl = unescapeXml(String(html[range]))
        }

        return result
    }

    enum Error: LocalizedError {
        case imageUrlNotFound

        var errorDescription: String? {
            switch self {
            case .imageUrlNotFound: return "Image URL not found in page"
            }
        }
    }
}

// MARK: - GalleryPageApiParser (解析 JSON API showpage 响应)

public enum GalleryPageApiParser {

    /// 解析 showpage API JSON 响应
    /// 对应 Android GalleryPageApiParser.parse
    public static func parse(_ data: Data) throws -> GalleryPageResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }

        var result = GalleryPageResult()

        // i3 字段包含图片 HTML: <img id="img" src="..." ...>
        if let i3 = json["i3"] as? String {
            let imgRegex = try! NSRegularExpression(pattern: #"src="([^"]+)""#)
            let range = NSRange(i3.startIndex..., in: i3)
            if let match = imgRegex.firstMatch(in: i3, range: range),
               let urlRange = Range(match.range(at: 1), in: i3) {
                result.imageUrl = GalleryPageParser.unescapeXml(String(i3[urlRange]))
            }
        }

        // i6 字段包含 skipHathKey
        if let i6 = json["i6"] as? String {
            let nlRegex = try! NSRegularExpression(pattern: #"nl\('([^']+)'\)"#)
            let range = NSRange(i6.startIndex..., in: i6)
            if let match = nlRegex.firstMatch(in: i6, range: range),
               let keyRange = Range(match.range(at: 1), in: i6) {
                result.skipHathKey = GalleryPageParser.unescapeXml(String(i6[keyRange]))
            }
        }

        // i7 字段包含原图链接
        if let i7 = json["i7"] as? String {
            let origRegex = try! NSRegularExpression(pattern: #"href="([^"]+)""#)
            let range = NSRange(i7.startIndex..., in: i7)
            if let match = origRegex.firstMatch(in: i7, range: range),
               let urlRange = Range(match.range(at: 1), in: i7) {
                result.originImageUrl = GalleryPageParser.unescapeXml(String(i7[urlRange]))
            }
        }

        // showKey (s字段)
        if let s = json["s"] as? String {
            result.showKey = s
        }

        return result
    }

    enum ParseError: LocalizedError {
        case invalidJSON
        var errorDescription: String? { "Invalid JSON response" }
    }
}

// GalleryPageResult — defined in EhModels
