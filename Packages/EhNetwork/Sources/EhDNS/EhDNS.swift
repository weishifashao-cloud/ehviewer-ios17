import Foundation
import EhSettings

// MARK: - EhDNS 自定义 DNS 解析 (对应 Android EhHosts.kt)
// 内置 IP 地址绕过 DNS 污染，支持中国用户直连
//
// ⚠️ 与 Android 的根本差异（决定了这条路能修到哪一步）：
//   Android 的 EhHosts 实现 okhttp3.Dns，`lookup()` 只决定「连哪个 IP」，
//   TLS 的 SNI 和证书校验仍使用 URL 里的域名，所以换 IP 不影响身份。
//   iOS 的 URLSession 没有等价接口，只能把 URL 的 host 换成 IP；
//   而 CFNetwork 对 IP 字面量**不发 SNI**（RFC 6066 禁止），于是：
//     · Cloudflare 前置的站点（e-hentai.org / forums）会直接中止握手；
//     · 单源服务器（ehgt.org）会返回默认证书，这时靠下面
//       DomainFrontingDelegate 用原始域名重做校验**有机会通过**。
//   实测记录（同一台机器、同一端口）：
//     185.132.132.76 带 SNI ehgt.org        → OK，SAN = ehgt.org
//     185.132.132.76 不带 SNI（IP 直连）    → 证书不匹配（IP address mismatch）
//     104.20.18.168  不带 SNI（Cloudflare） → 握手失败
//
// 因此内置表的作用是「尽力而为的兜底」，真正可靠的是 DoH（见 resolveViaDoH）。

public final class EhDNS: @unchecked Sendable {
    public static let shared = EhDNS()

    /// 是否启用自定义 DNS — 从 AppSettings 读取，与设置界面联动
    public var isEnabled: Bool {
        AppSettings.shared.builtInHosts || AppSettings.shared.domainFronting || AppSettings.shared.dnsOverHttps
    }

    /// 内置 Hosts 映射
    ///
    /// 2026-11 与安卓端 xiaojieonly/Ehviewer_CN_SXJ 的 EhHosts.java 对齐，
    /// 并逐条做了可达性实测。与上一版的差异：
    ///
    ///   · ehgt.org：原来是 37.48.89.44 / 81.171.10.48 / 178.162.139.24，
    ///     实测**全部超时**；换成安卓表的 185.132.132.76/79 + 62.112.8.152，
    ///     实测 TLS 1.3 握手正常且证书 SAN 就是 ehgt.org。
    ///   · e-hentai.org：补上 172.66.132.196 / 172.66.140.62（安卓新增的两个，
    ///     DNSPod DoH 当前返回的也正是这两个）。
    ///   · forums.e-hentai.org：换成 172.66.132.196 / 172.66.140.62。
    ///   · repo / upld.e-hentai.org：原来填的是 94.100.x（Mail.ru 旧段，早已不用），
    ///     改用当前 Leaseweb 段。
    ///   · 删除 api.e-hentai.org、upload.e-hentai.org：填的是早已失效的老 IP，
    ///     而且安卓端没有这两项；交给 DoH 动态解析更可靠。
    ///   · 删除 gt0~3.ehgt.org：这几个子域的证书**只覆盖 ehgt.org / www.ehgt.org**，
    ///     即使 IP 可达，按子域名校验也必然失败（实测 Hostname mismatch），
    ///     保留只会拖慢回退。
    ///   · raw.githubusercontent.com 保留 185.199.108-111.133：实测仍返回
    ///     `*.githubusercontent.com` 的有效证书。
    private static let builtInHosts: [String: [String]] = [
        // E-Hentai 主站（Cloudflare）
        "e-hentai.org": [
            "104.20.18.168", "104.20.19.168",
            "172.66.132.196", "172.66.140.62",
            "172.67.2.238",
        ],
        "forums.e-hentai.org": ["172.66.132.196", "172.66.140.62"],

        // Repo / 上传（Leaseweb）
        "repo.e-hentai.org": ["85.17.247.144", "95.211.142.153"],
        "upld.e-hentai.org": ["95.211.142.153", "85.17.247.144"],

        // 缩略图 CDN（单源，证书覆盖 ehgt.org）
        "ehgt.org": ["185.132.132.76", "185.132.132.79", "62.112.8.152"],

        // ExHentai（专用段，变动比主站频繁，由 builtExHosts 单独控制）
        "exhentai.org": [
            "178.175.128.251", "178.175.128.252", "178.175.128.253", "178.175.128.254",
            "178.175.129.251", "178.175.129.252", "178.175.129.253", "178.175.129.254",
            "178.175.132.19", "178.175.132.20", "178.175.132.21", "178.175.132.22",
        ],
        "s.exhentai.org": [
            "178.175.129.253", "178.175.129.254",
            "178.175.128.253", "178.175.128.254",
            "178.175.132.21", "178.175.132.22",
        ],
        "upld.exhentai.org": ["178.175.132.22", "178.175.129.254", "178.175.128.254"],

        // Repo / Raw
        "raw.githubusercontent.com": [
            "185.199.108.133", "185.199.109.133",
            "185.199.110.133", "185.199.111.133",
        ],
    ]

    /// 用户自定义 Hosts (优先于内置)
    private var userHosts: [String: [String]] = [:]
    /// 用于保护 userHosts 的并发访问
    private let lock = NSLock()

    /// DoH 结果缓存：避免每次请求都打一次 DoH
    private var dohCache: [String: (ips: [String], expires: Date)] = [:]
    private let dohCacheLock = NSLock()
    private static let dohTTL: TimeInterval = 600

    /// DNS-over-HTTPS 提供商 URL
    ///
    /// dnspod 排第一：国内可达，且实测对 e-hentai.org 返回的是当前真实地址
    /// （172.66.132.196 / 172.66.140.62）。cloudflare / google 在国内常被拦截，
    /// 作为第二顺位兜底。AliDNS 实测会返回污染结果（曾返回 Facebook 段），
    /// 保留但不进默认链。
    public enum DoHProvider: String, CaseIterable, Sendable {
        case dnspod = "https://doh.pub/dns-query"
        case cloudflare = "https://cloudflare-dns.com/dns-query"
        case google = "https://dns.google/dns-query"
        case aliDNS = "https://dns.alidns.com/dns-query"
    }

    /// 默认尝试顺序
    private static let defaultProviderChain: [DoHProvider] = [.dnspod, .cloudflare]

    /// 自定义 hosts 的持久化位置
    private static let userHostsKey = "user_hosts"

    private init() {
        // 自定义 hosts 之前只存在内存里，重启就没了 —— 从 UserDefaults 恢复
        if let stored = UserDefaults.standard.dictionary(forKey: Self.userHostsKey) as? [String: [String]] {
            userHosts = stored
        }
    }

    /// 当前所有自定义 hosts (供设置界面展示)
    public func allUserHosts() -> [String: [String]] {
        lock.lock()
        defer { lock.unlock() }
        return userHosts
    }

    private func persistUserHosts() {
        // 已在 lock 内调用
        UserDefaults.standard.set(userHosts, forKey: Self.userHostsKey)
    }

    // MARK: - 解析

    /// 获取指定主机名的 IP 地址列表
    /// 对齐 Android: 随机打乱实现负载均衡
    public func resolve(host: String) -> [String] {
        guard isEnabled else { return [] }
        return forceResolve(host: host)
    }

    /// 异步解析 — 优先使用 DNS-over-HTTPS（若启用），回退到内置 Hosts
    /// 调用方在需要动态解析时应优先使用此方法
    public func resolveAsync(host: String) async -> [String] {
        guard isEnabled else { return [] }

        // 如果用户启用了 DoH，优先走 DoH
        if AppSettings.shared.dnsOverHttps {
            let ips = await resolveViaDoHChained(host: host)
            if !ips.isEmpty { return ips }
        }

        // 回退到内置 Hosts 解析
        return forceResolve(host: host)
    }

    /// 域名前置专用解析 —— 回退链路真正调用的就是这个。
    ///
    /// 与 Android 的一处**刻意不同**：DoH 与内置表**合并**，而不是二选一。
    /// 原因是这次对照实测发现两件事：
    ///   · 内置表会过期（ehgt.org 那一组 IP 已全部超时，安卓表里的才是活的）；
    ///   · DoH 也不是万灵药（DNSPod 对 s.exhentai.org 返回过 Facebook 段）。
    /// 所以两边都给，去重后按「DoH 在前、内置在后」排列，前面失败还能落到后面。
    ///
    /// 返回顺序：用户自定义 → DoH → 内置表。
    public func resolveForFronting(host: String) async -> [String] {
        // 1) 用户自定义最优先（用户明确指定过，说明他自己验证过）
        lock.lock()
        let userIps = userHosts[host]
        lock.unlock()
        if let ips = userIps, !ips.isEmpty {
            return ips.shuffled()
        }

        var merged: [String] = []
        var seen = Set<String>()
        func append(_ list: [String]) {
            for ip in list.shuffled() where seen.insert(ip).inserted {
                merged.append(ip)
            }
        }

        // 2) DoH：能拿到当前真实地址，也能覆盖内置表里没有的域名（如 H@H 节点）
        if AppSettings.shared.dnsOverHttps {
            append(await resolveViaDoHChained(host: host))
        }

        // 3) 内置表兜底
        // ExHentai 的内置 IP 单独由 builtExHosts 控制 (对齐 Android 的两个独立开关):
        // 这批 IP 变动比主站频繁，写死的表过期时反而会挡住能正常解析的用户
        if !Self.isExHentaiHost(host) || AppSettings.shared.builtExHosts {
            append(Self.builtInHosts[host] ?? [])
        }

        return merged
    }

    /// 强制解析 — 无视 isEnabled 设置，直接从内置 Hosts 解析
    /// 用于: VPN 代理 503 回退时，绕过 HTTP 代理同时使用真实 IP (非 fake-ip)
    private static func isExHentaiHost(_ host: String) -> Bool {
        host == "exhentai.org" || host.hasSuffix(".exhentai.org")
    }

    public func forceResolve(host: String) -> [String] {
        // 用户自定义优先
        lock.lock()
        let userIps = userHosts[host]
        lock.unlock()
        if let ips = userIps, !ips.isEmpty {
            return ips.shuffled()  // 对齐 Android: Collections.shuffle()
        }
        // 回退到内置
        if Self.isExHentaiHost(host), !AppSettings.shared.builtExHosts {
            return []
        }
        if let ips = Self.builtInHosts[host], !ips.isEmpty {
            return ips.shuffled()  // 对齐 Android: Collections.shuffle()
        }
        return []  // 回退到系统 DNS
    }

    // MARK: - DNS over HTTPS

    /// 使用 DNS-over-HTTPS 异步解析域名
    public func resolveViaDoH(host: String, provider: DoHProvider = .dnspod) async throws -> [String] {
        guard let url = URL(string: "\(provider.rawValue)?name=\(host)&type=A") else {
            throw EhDNSError.invalidUrl
        }

        var request = URLRequest(url: url)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = json["Answer"] as? [[String: Any]]
        else {
            throw EhDNSError.parseError
        }

        let ips = answers.compactMap { answer -> String? in
            guard let type = answer["type"] as? Int, type == 1,
                  let data = answer["data"] as? String,
                  // 只取 IPv4：URL 改写为 IPv6 字面量需要方括号，
                  // 而 URLSession 在 host 含冒号时容易拼出非法 URL，这里直接跳过。
                  !data.contains(":")
            else { return nil }
            return data
        }

        return ips
    }

    /// 按默认链依次尝试，带 TTL 缓存。
    /// 全部失败返回空数组（调用方回退到内置表），不抛错。
    public func resolveViaDoHChained(host: String) async -> [String] {
        if let cached = cachedDoH(host) { return cached }

        for provider in Self.defaultProviderChain {
            guard let raw = try? await resolveViaDoH(host: host, provider: provider) else { continue }
            // 有些域名连 DoH 也会返回污染地址（实测 DNSPod 把 s.exhentai.org
            // 解析到了 Facebook 段），明显错误的先剔掉再决定是否采用。
            let ips = raw.filter { !Self.isKnownSinkhole($0) }
            if !ips.isEmpty {
                storeDoH(host, ips)
                return ips
            }
        }
        return []
    }

    /// 已知的污染落地段（Facebook / Twitter）。
    ///
    /// DNS 污染最典型的特征就是把这些域名指向这几家的地址 —— 实测本机系统 DNS
    /// 和 AliDNS 都返回过。这些段不可能是 E-Hentai 的基础设施，命中即丢弃。
    /// 这只是一道「明显错误」的过滤，不是安全机制。
    private static func isKnownSinkhole(_ ip: String) -> Bool {
        let prefixes = [
            "31.13.", "157.240.", "66.220.", "179.60.", "185.89.",      // Facebook
            "199.16.", "199.59.", "104.244.42.", "192.133.", "108.160.", // Twitter
        ]
        return prefixes.contains { ip.hasPrefix($0) }
    }

    private func cachedDoH(_ host: String) -> [String]? {
        dohCacheLock.lock()
        defer { dohCacheLock.unlock() }
        guard let entry = dohCache[host], entry.expires > Date() else { return nil }
        return entry.ips
    }

    private func storeDoH(_ host: String, _ ips: [String]) {
        dohCacheLock.lock()
        defer { dohCacheLock.unlock() }
        // 表太大就整体清一次，别让它无限长（阅读时会出现大量 H@H 子域）
        if dohCache.count > 256 { dohCache.removeAll() }
        dohCache[host] = (ips, Date().addingTimeInterval(Self.dohTTL))
    }

    // MARK: - 用户自定义

    public func setUserHost(_ host: String, ips: [String]) {
        lock.lock()
        userHosts[host] = ips
        persistUserHosts()
        lock.unlock()
    }

    public func removeUserHost(_ host: String) {
        lock.lock()
        userHosts.removeValue(forKey: host)
        persistUserHosts()
        lock.unlock()
    }

    public func clearUserHosts() {
        lock.lock()
        userHosts.removeAll()
        persistUserHosts()
        lock.unlock()
    }

    // MARK: - URLSession 集成 (Domain Fronting)

    /// 替换请求 URL 中的域名为 IP (手动 Domain Fronting)
    /// 对应 Android OkHttp Dns 接口的自动 DNS 替换
    /// 仅在 isEnabled 为 true 时生效
    public func applyDomainFronting(to request: URLRequest) -> URLRequest {
        guard isEnabled else { return request }
        return forceDomainFronting(to: request)
    }

    /// 强制域名前置 — 无视 isEnabled 设置
    /// 用于: VPN 代理 503 回退时，绕过 HTTP 代理同时使用内置 DNS 真实 IP
    /// 避免 Clash fake-ip 模式下 TLS 握手失败
    public func forceDomainFronting(to request: URLRequest) -> URLRequest {
        guard let url = request.url, let host = url.host else { return request }
        let ips = forceResolve(host: host)
        guard let ip = ips.first else { return request }  // 无内置 IP 则原样返回
        return makeFrontedRequest(request, ip: ip) ?? request
    }

    /// 把请求的目标 host 换成指定 IP，同时保留原始 Host 头与 Cookie。
    ///
    /// 返回 nil 表示这个 IP 无法安全地写进 URL（例如 IPv6 字面量）。
    /// 与 `forceDomainFronting` 的区别是 IP 由调用方给：回退链路是先异步解析
    /// （DoH 可能给出多个），再逐个试，遇到死 IP 不至于整次回退作废。
    public func makeFrontedRequest(_ request: URLRequest, ip: String) -> URLRequest? {
        guard let url = request.url, let host = url.host else { return nil }
        // IPv6 需要在 URL 里加方括号，Foundation 各版本对 URLComponents.host
        // 是否自动加括号的行为不一致，这里直接拒绝，交给 DoH 的 A 记录。
        guard !ip.contains(":") else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = ip

        guard let newUrl = components?.url else { return nil }

        var modifiedRequest = URLRequest(url: newUrl)
        modifiedRequest.allHTTPHeaderFields = request.allHTTPHeaderFields
        modifiedRequest.httpMethod = request.httpMethod
        modifiedRequest.httpBody = request.httpBody
        modifiedRequest.timeoutInterval = request.timeoutInterval
        // 设置原始 Host 头 (关键: TLS delegate 会从此 header 读取原始域名做证书验证)
        modifiedRequest.setValue(host, forHTTPHeaderField: "Host")

        // 手动携带 Cookie (关键: URL 域名变成 IP 后, HTTPCookieStorage 不会自动匹配 cookies)
        if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                // 如果原始请求已有 Cookie header, 合并; 否则直接设置
                if let existing = modifiedRequest.value(forHTTPHeaderField: key), !existing.isEmpty {
                    modifiedRequest.setValue("\(existing); \(value)", forHTTPHeaderField: key)
                } else {
                    modifiedRequest.setValue(value, forHTTPHeaderField: key)
                }
            }
        }

        return modifiedRequest
    }
}

// MARK: - 错误类型

public enum EhDNSError: LocalizedError, Sendable {
    case invalidUrl
    case parseError
    case noResult

    public var errorDescription: String? {
        switch self {
        case .invalidUrl: return "Invalid DoH URL"
        case .parseError: return "Failed to parse DNS response"
        case .noResult: return "No DNS result found"
        }
    }
}
