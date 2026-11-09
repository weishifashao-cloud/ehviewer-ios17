import Foundation
import EhDNS

// MARK: - 带直连回退的请求执行器
//
// App 里有几条链路直接用裸 URLSession 取数据，绕过了 EhAPI 的回退逻辑：
//   · CachedAsyncImage —— 全部缩略图
//   · SpriteSheetCache —— 「查看全部预览」的雪碧图
//   · ReaderViewModel.fetchPToken —— 阅读器每 20 页抓一次 pToken
// 在 DNS 被污染的网络里，它们会稳定失败，而 EhAPI 那条路径即使修好了也用不上。
//
// 这里把「先正常请求、失败后直连」封成一个入口，让这些链路也走同一条通道。

public enum EhDirectFetch {

    /// 先走 `session`，失败后按 EhDNS 的解析结果逐个 IP 直连（保持 SNI）。
    public static func data(
        for request: URLRequest,
        using session: URLSession
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            let original = error
            guard shouldRetryDirectly(error) else { throw original }
            do {
                return try await directData(for: request)
            } catch {
                // 直连也失败，抛原始错误 —— 用户对那个更熟悉
                throw original
            }
        }
    }

    /// 只走直连通道，不先试普通请求。用于诊断与已经确定失败的场景。
    public static func directData(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let host = request.url?.host else { throw URLError(.badURL) }

        let candidates = await EhDNS.shared.resolveForFronting(host: host)
        guard !candidates.isEmpty else { throw URLError(.cannotFindHost) }

        var lastError: Error = URLError(.cannotFindHost)
        for ip in candidates.prefix(3) {
            do {
                return try await DirectTLSClient.shared.perform(request, ip: ip, host: host)
            } catch {
                lastError = error
                // 结构性失败（TLS 被拒 / 响应不是 HTTP）换 IP 也一样，别白等
                if DirectTLSClient.isFatal(error) { break }
            }
        }
        throw lastError
    }

    /// 与 EhAPI 内部保持同一套口径：除了明确不该重试的，其余都试一次直连。
    private static func shouldRetryDirectly(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cancelled, .userCancelledAuthentication, .notConnectedToInternet:
            return false
        default:
            return true
        }
    }
}
