import Foundation

// MARK: - FavListUrlBuilder (对应 Android FavListUrlBuilder.java)
// 收藏列表 URL 构建器

public struct FavListUrlBuilder: Sendable, Codable {

    // MARK: - 常量

    public static let favCatAll: Int   = -1   // 全部收藏
    public static let favCatLocal: Int = -2   // 本地收藏

    // MARK: - 属性

    public var index: Int = 0
    public var keyword: String?
    public var favCat: Int = Self.favCatAll

    public init() {}

    public init(favCat: Int = Self.favCatAll, keyword: String? = nil, index: Int = 0) {
        self.favCat = favCat
        self.keyword = keyword
        self.index = index
    }

    // MARK: - 辅助

    public static func isValidFavCat(_ cat: Int) -> Bool {
        cat >= 0 && cat <= 9
    }

    public var isLocalFavCat: Bool {
        favCat == Self.favCatLocal
    }

    // MARK: - 构建 URL (对应 Android build())

    public func build(site: EhSite = .eHentai) -> String {
        var params: [String] = []

        // 收藏分类
        if Self.isValidFavCat(favCat) {
            params.append("favcat=\(favCat)")
        }
        // favCatAll 时不加 favcat 参数 (对齐 Android 注释代码)

        // 搜索关键词
        if let kw = keyword, !kw.isEmpty {
            if let encoded = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                params.append("f_search=\(encoded)")
                // 搜索范围: Name / Tags / Note (对齐 Android)
                params.append("sn=on")
                params.append("st=on")
                params.append("sf=on")
            }
        }

        // 分页
        if index > 0 {
            params.append("page=\(index)")
        }

        let baseUrl = EhURL.favoritesUrl(for: site)
        if params.isEmpty {
            return baseUrl
        }
        return baseUrl + "?" + params.joined(separator: "&")
    }
}
