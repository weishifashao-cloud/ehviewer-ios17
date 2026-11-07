import Foundation

// MARK: - AppConfig (对应 Android AppConfig.java)
// 文件系统目录管理

public enum AppConfig {

    // MARK: - 应用目录

    /// Documents 目录 (用户可见)
    public static var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Caches 目录
    public static var cachesDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    /// Application Support 目录
    public static var appSupportDir: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 临时目录
    public static var tempDir: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }

    // MARK: - 功能子目录 (对应 Android AppConfig 各 getXxxDir 方法)

    /// 下载根目录 (对应 Android getDefaultDownloadDir)
    public static var downloadDir: URL {
        let url = documentsDir.appendingPathComponent("download", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 临时下载目录
    public static var tempDownloadDir: URL {
        let url = cachesDir.appendingPathComponent("download_temp", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 归档目录 (对应 Android getArchiverDir)
    public static var archiverDir: URL {
        let url = documentsDir.appendingPathComponent("archiver", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 图片导出目录
    public static var imageDir: URL {
        let url = documentsDir.appendingPathComponent("image", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 解析错误记录目录 (对应 Android getParseErrorDir)
    public static var parseErrorDir: URL {
        let url = cachesDir.appendingPathComponent("parse_error", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 崩溃日志目录
    public static var crashDir: URL {
        let url = cachesDir.appendingPathComponent("crash", isDirectory: true)
        ensureDir(url)
        return url
    }

    /// 数据库目录
    public static var databaseDir: URL {
        let url = appSupportDir.appendingPathComponent("database", isDirectory: true)
        ensureDir(url)
        return url
    }

    // MARK: - 特定画廊下载目录

    /// 获取画廊的下载目录 (gid-token 格式)
    public static func galleryDownloadDir(gid: Int64, token: String) -> URL {
        downloadDir.appendingPathComponent("\(gid)-\(token)", isDirectory: true)
    }

    /// 获取画廊的 SpiderInfo 文件路径
    public static func spiderInfoFile(gid: Int64, token: String) -> URL {
        galleryDownloadDir(gid: gid, token: token).appendingPathComponent(".ehviewer")
    }

    // MARK: - 文件大小

    /// 计算目录大小 (字节)
    public static func dirSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = attrs.fileSize else { continue }
            totalSize += Int64(fileSize)
        }
        return totalSize
    }

    /// 清空目录
    public static func clearDir(at url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }

    // MARK: - Save parse error body (对应 Android saveParseErrorBody)

    /// 保存解析错误的 HTML body 以便调试
    public static func saveParseErrorBody(_ body: String, name: String = "error") {
        let filename = "\(name)_\(Int(Date.now.timeIntervalSince1970)).html"
        let fileURL = parseErrorDir.appendingPathComponent(filename)
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - 辅助

    private static func ensureDir(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
