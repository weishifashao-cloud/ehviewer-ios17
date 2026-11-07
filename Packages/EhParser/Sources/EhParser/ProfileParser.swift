import Foundation
import EhModels
import SwiftSoup

// MARK: - 用户资料解析器 (对应 Android ProfileParser.java)

public enum ProfileParser {

    /// 从用户资料页面提取 displayName 和 avatar
    /// 对应 Android ProfileParser.parse
    public static func parse(_ body: String) throws -> ProfileResult {
        let doc = try SwiftSoup.parse(body)
        var result = ProfileResult()

        guard let profilename = try doc.getElementById("profilename") else {
            throw ParserError.missingElement("#profilename")
        }

        result.displayName = try profilename.child(0).text()

        // avatar: profilename 的下下一个兄弟元素的第一个子元素的 src
        // 对应 Android: profilename.nextElementSibling().nextElementSibling().child(0).attr("src")
        do {
            if let sib1 = try profilename.nextElementSibling(),
               let sib2 = try sib1.nextElementSibling() {
                let avatar = try sib2.child(0).attr("src")
                if !avatar.isEmpty {
                    if avatar.hasPrefix("http") {
                        result.avatar = avatar
                    } else {
                        result.avatar = "https://forums.e-hentai.org/" + avatar
                    }
                }
            }
        } catch {
            // No avatar, 对应 Android Log.i(TAG, "No avatar")
        }

        return result
    }
}
