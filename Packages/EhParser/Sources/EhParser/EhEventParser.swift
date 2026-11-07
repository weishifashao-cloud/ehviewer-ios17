import Foundation
import SwiftSoup
import EhModels

// MARK: - EhEventParser (对应 Android EhEventParse.java)
// 解析首页活动/公告栏内容

public enum EhEventParser {

    /// 解析事件公告 (对应 Android parse)
    /// 提取 #eventpane 的 innerHTML
    public static func parse(_ body: String) -> String? {
        guard let doc = try? SwiftSoup.parse(body),
              let eventPane = try? doc.select("#eventpane").first()
        else {
            return nil
        }

        let html = try? eventPane.html()
        guard let result = html, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return result
    }
}
