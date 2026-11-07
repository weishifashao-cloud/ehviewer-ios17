import Foundation
import EhModels

// MARK: - GalleryTokenApiParser (对应 Android GalleryTokenApiParser.java)
// 已内联在 EhAPI.getGalleryToken 中，此文件提供独立可复用版本

public enum GalleryTokenApiParser {

    /// 解析 gtoken API 响应
    /// - Returns: 页面 token
    public static func parse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokenList = json["tokenlist"] as? [[String: Any]],
              let first = tokenList.first,
              let token = first["token"] as? String
        else {
            // 检查 error 字段
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw EhParseError.parseFailure(error)
            }
            throw EhParseError.parseFailure("Failed to parse gtoken response")
        }
        return token
    }
}

// MARK: - VoteCommentParser (对应 Android VoteCommentParser.java)
// 已内联在 EhAPI.voteComment 中，此文件提供独立可复用版本

public enum VoteCommentParser {

    /// 解析 votecomment API 响应
    public static func parse(_ data: Data) throws -> VoteCommentResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EhParseError.parseFailure("Invalid votecomment JSON")
        }

        guard let score = json["comment_score"] as? Int,
              let vote = json["comment_vote"] as? Int
        else {
            // 检查 error 字段
            if let error = json["error"] as? String {
                throw EhParseError.parseFailure(error)
            }
            throw EhParseError.parseFailure("Missing comment_score or comment_vote")
        }

        return VoteCommentResult(score: score, vote: vote)
    }
}
