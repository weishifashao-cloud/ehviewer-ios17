import Foundation

// MARK: - 画廊详情 (对应 Android GalleryDetail.java)

public struct GalleryDetail: Sendable, Codable {
    // MARK: 基础信息 (来自 GalleryInfo)
    public var info: GalleryInfo

    // MARK: API 凭证 (从页面内联 JS 提取)
    public var apiUid: Int64
    public var apiKey: String

    // MARK: 扩展元数据
    public var torrentCount: Int
    public var torrentUrl: String?
    public var archiveUrl: String?
    public var parent: String?
    public var visible: String?
    public var language: String?
    public var size: String?
    public var favoriteCount: Int
    public var isFavorited: Bool
    public var ratingCount: Int

    // MARK: 标签 (分组)
    public var tags: [GalleryTagGroup]

    // MARK: 评论
    public var comments: GalleryCommentList

    // MARK: 预览
    public var previewPages: Int
    public var previewSet: PreviewSet?

    // MARK: Spider 信息 (用于阅读器)
    public var spiderInfoPages: Int
    public var spiderInfoPreviewPages: Int
    public var spiderInfoPreviewSet: PreviewSet?

    // MARK: 版本更新
    public var newVersions: [NewVersion]

    public init(
        info: GalleryInfo = GalleryInfo(),
        apiUid: Int64 = -1,
        apiKey: String = "",
        torrentCount: Int = 0,
        torrentUrl: String? = nil,
        archiveUrl: String? = nil,
        parent: String? = nil,
        visible: String? = nil,
        language: String? = nil,
        size: String? = nil,
        favoriteCount: Int = 0,
        isFavorited: Bool = false,
        ratingCount: Int = 0,
        tags: [GalleryTagGroup] = [],
        comments: GalleryCommentList = GalleryCommentList(),
        previewPages: Int = 0,
        previewSet: PreviewSet? = nil,
        spiderInfoPages: Int = 0,
        spiderInfoPreviewPages: Int = 0,
        spiderInfoPreviewSet: PreviewSet? = nil,
        newVersions: [NewVersion] = []
    ) {
        self.info = info
        self.apiUid = apiUid
        self.apiKey = apiKey
        self.torrentCount = torrentCount
        self.torrentUrl = torrentUrl
        self.archiveUrl = archiveUrl
        self.parent = parent
        self.visible = visible
        self.language = language
        self.size = size
        self.favoriteCount = favoriteCount
        self.isFavorited = isFavorited
        self.ratingCount = ratingCount
        self.tags = tags
        self.comments = comments
        self.previewPages = previewPages
        self.previewSet = previewSet
        self.spiderInfoPages = spiderInfoPages
        self.spiderInfoPreviewPages = spiderInfoPreviewPages
        self.spiderInfoPreviewSet = spiderInfoPreviewSet
        self.newVersions = newVersions
    }
}

// MARK: - 标签组

public struct GalleryTagGroup: Sendable, Codable {
    public var groupName: String  // 命名空间: "artist", "female", "male", etc.
    public var tags: [String]

    public init(groupName: String = "", tags: [String] = []) {
        self.groupName = groupName
        self.tags = tags
    }
}

// MARK: - 评论

public struct GalleryComment: Identifiable, Sendable, Codable {
    public var id: Int64           // 0 = 上传者评论 (不可投票)
    public var score: Int
    public var editable: Bool
    public var voteUpAble: Bool
    public var voteUpEd: Bool
    public var voteDownAble: Bool
    public var voteDownEd: Bool
    public var voteState: String?
    public var time: Date
    public var user: String
    public var comment: String     // HTML 内容
    public var lastEdited: Date?

    public init(
        id: Int64 = 0, score: Int = 0, editable: Bool = false,
        voteUpAble: Bool = false, voteUpEd: Bool = false,
        voteDownAble: Bool = false, voteDownEd: Bool = false,
        voteState: String? = nil, time: Date = .now, user: String = "",
        comment: String = "", lastEdited: Date? = nil
    ) {
        self.id = id; self.score = score; self.editable = editable
        self.voteUpAble = voteUpAble; self.voteUpEd = voteUpEd
        self.voteDownAble = voteDownAble; self.voteDownEd = voteDownEd
        self.voteState = voteState; self.time = time; self.user = user
        self.comment = comment; self.lastEdited = lastEdited
    }
}

public struct GalleryCommentList: Sendable, Codable {
    public var comments: [GalleryComment]
    public var hasMore: Bool

    public init(comments: [GalleryComment] = [], hasMore: Bool = false) {
        self.comments = comments
        self.hasMore = hasMore
    }
}

// MARK: - 预览集 (对应 Android NormalPreviewSet / LargePreviewSet)

public enum PreviewSet: Sendable, Codable {
    /// 雪碧图模式: 单张大图裁剪出多个预览
    case normal([NormalPreview])
    /// 独立大图模式: 每个预览一张图
    case large([LargePreview])

    public var count: Int {
        switch self {
        case .normal(let items): return items.count
        case .large(let items): return items.count
        }
    }
    
    public var isEmpty: Bool {
        count == 0
    }

    public func pageUrl(at index: Int) -> String? {
        switch self {
        case .normal(let items): return items[safe: index]?.pageUrl
        case .large(let items): return items[safe: index]?.pageUrl
        }
    }

    public func position(at index: Int) -> Int? {
        switch self {
        case .normal(let items): return items[safe: index]?.position
        case .large(let items): return items[safe: index]?.position
        }
    }
}

public struct NormalPreview: Sendable, Codable {
    public var position: Int
    public var imageUrl: String
    public var pageUrl: String
    public var offsetX: Int
    public var offsetY: Int
    public var clipWidth: Int
    public var clipHeight: Int

    public init(position: Int = 0, imageUrl: String = "", pageUrl: String = "",
                offsetX: Int = 0, offsetY: Int = 0, clipWidth: Int = 0, clipHeight: Int = 0) {
        self.position = position; self.imageUrl = imageUrl; self.pageUrl = pageUrl
        self.offsetX = offsetX; self.offsetY = offsetY
        self.clipWidth = clipWidth; self.clipHeight = clipHeight
    }
}

public struct LargePreview: Sendable, Codable {
    public var position: Int
    public var imageUrl: String
    public var pageUrl: String

    public init(position: Int = 0, imageUrl: String = "", pageUrl: String = "") {
        self.position = position; self.imageUrl = imageUrl; self.pageUrl = pageUrl
    }
}

// MARK: - 版本更新

public struct NewVersion: Sendable, Codable {
    public var gid: Int64
    public var token: String
    public var name: String
    public var posted: String

    public init(gid: Int64 = 0, token: String = "", name: String = "", posted: String = "") {
        self.gid = gid; self.token = token; self.name = name; self.posted = posted
    }
}

// MARK: - Safe subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
