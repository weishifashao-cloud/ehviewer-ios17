import Foundation
import EhModels

// MARK: - RateGalleryParser (对应 Android RateGalleryParser.java)
// 解析 rategallery JSON API 响应

public enum RateGalleryParser {

    /// 解析评分响应
    public static func parse(_ data: Data) throws -> RateResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EhParseError.parseFailure("Invalid rategallery JSON")
        }

        // rating_avg: Float (可能是 Double 或 String)
        let rating: Float
        if let r = json["rating_avg"] as? Double {
            rating = Float(r)
        } else if let r = json["rating_avg"] as? String, let f = Float(r) {
            rating = f
        } else {
            throw EhParseError.parseFailure("Missing rating_avg")
        }

        // rating_cnt: Int
        let ratingCount: Int
        if let c = json["rating_cnt"] as? Int {
            ratingCount = c
        } else if let c = json["rating_cnt"] as? String, let i = Int(c) {
            ratingCount = i
        } else {
            throw EhParseError.parseFailure("Missing rating_cnt")
        }

        return RateResult(rating: rating, ratingCount: ratingCount)
    }
}
