# 贡献指南

感谢你对 EhViewer-Apple 的关注！我们欢迎各种形式的贡献。

## 🚀 如何贡献

### 报告 Bug

1. 在 [Issues](https://github.com/felixchaos/EhViewer-Apple/issues) 页面搜索是否已有相同问题
2. 如果没有，创建新 Issue 并使用 **Bug Report** 模板
3. 尽可能提供详细信息：设备型号、系统版本、复现步骤、截图/录屏

### 功能建议

1. 在 [Issues](https://github.com/felixchaos/EhViewer-Apple/issues) 页面创建新 Issue
2. 使用 **Feature Request** 模板
3. 描述你期望的功能和使用场景

### 提交代码

1. **Fork** 本仓库
2. 创建功能分支：
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. 编写代码并提交：
   ```bash
   git commit -m "feat: 简要描述你的更改"
   ```
4. 推送到你的 Fork：
   ```bash
   git push origin feature/your-feature-name
   ```
5. 创建 **Pull Request**

## 📝 Commit 规范

我们使用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 规范：

| 类型 | 说明 |
|------|------|
| `feat` | 新功能 |
| `fix` | Bug 修复 |
| `docs` | 文档更新 |
| `style` | 代码格式（不影响功能） |
| `refactor` | 重构（不是新功能也不是修复） |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `chore` | 构建/工具链/CI 相关 |

示例：
```
feat: 添加画廊评论功能
fix: 修复下载进度未更新的问题
docs: 更新 README 安装说明
```

## 🏗️ 开发环境

### 环境要求

- **Xcode 16.0+**
- **Swift 6.0**
- **iOS 17.0+** / **macOS 14.0+**

### 项目架构

项目采用 Swift Package Manager 模块化架构：

- **EhCore** — 数据模型、数据库、设置
- **EhNetwork** — 网络请求、Cookie、DNS
- **EhParser** — HTML/JSON 解析
- **EhSpider** — 图片抓取引擎
- **EhDownload** — 下载管理
- **EhUI** — 可复用 UI 组件

### 本地开发

```bash
git clone https://github.com/felixchaos/EhViewer-Apple.git
cd EhViewer-Apple
open "ehviewer apple.xcodeproj"
```

## 🔍 代码规范

- 使用 Swift 6 严格并发安全 (`Sendable`, `@MainActor`)
- 遵循 SwiftUI 最佳实践
- 用户可见文本使用中文
- 错误信息需清晰、对用户友好
- 注释使用中文或英文均可

## 📋 Pull Request 规范

- PR 标题遵循 Commit 规范
- 描述中说明：改了什么、为什么改、如何测试
- 确保项目在 iOS 和 macOS 上都能编译通过
- 如有 UI 变更，附上截图

## ❓ 有问题？

- 开一个 [Discussion](https://github.com/felixchaos/EhViewer-Apple/discussions) 或 Issue
- 注明你的环境信息（Xcode 版本、系统版本等）

再次感谢你的贡献！ ❤️
