//
//  NavigationComponents.swift
//  ehviewer apple
//
//  全局导航规范组件:
//  1. AppBackButton — 统一返回按钮 (Chevron 圆形半透明)
//  2. EdgeSwipeBackModifier — 恢复边缘滑动返回手势
//  3. NavigationBarCompact — 强制 inline 标题栏修饰符
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - 1. 统一返回按钮 (对齐 Android Toolbar NavigationIcon)

/// 全局统一返回按钮 — 所有二级及深层页面使用同一样式
///
/// 样式: Chevron 图标 + 半透明圆形背景
/// 位置: 左上角叠加 (overlay alignment: .topLeading)
///
/// 使用方式:
/// ```swift
/// .overlay(alignment: .topLeading) {
///     AppBackButton { dismiss() }
/// }
/// ```
struct AppBackButton: View {
    let action: () -> Void
    
    /// 背景风格: 当页面有深色/图片背景时使用 dark, 普通页面用 light
    var style: Style = .dark
    
    enum Style {
        case dark   // 白色图标 + 黑色半透明背景 (用于图片/深色背景上)
        case light  // 系统颜色 + 浅色材质背景 (用于普通列表页)
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(style == .dark ? .white : Color.primary)
                .padding(8)
                .background(
                    style == .dark
                        ? AnyShapeStyle(.black.opacity(0.5))
                        : AnyShapeStyle(.ultraThinMaterial)
                )
                .clipShape(Circle())
        }
        .accessibilityLabel("返回")
    }
}

// MARK: - 2. 边缘滑动返回手势修复

/// 修复 SwiftUI 隐藏原生返回按钮后边缘滑动返回手势失效的问题
///
/// 使用方式:
/// ```swift
/// NavigationStack { content }
///     .enableEdgeSwipeBack()
/// ```
///
/// ⚠️ iOS 17 上默认不要再挂这个修饰符（见 GalleryDetailView 的说明）。
#if os(iOS)
struct EdgeSwipeBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EdgeSwipeBackHelper())
    }
}

private struct EdgeSwipeBackHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        EdgeSwipeBackViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// 只做一件事：系统把 interactivePopGestureRecognizer 关掉了，就把它重新打开。
///
/// ⚠️ 绝对不能改它的 delegate。
///
/// 原实现把 `interactivePopGestureRecognizer.delegate` 换成了 UINavigationController
/// 自己，并给 UINavigationController 加了一个**进程级**的
/// `UIGestureRecognizerDelegate` 扩展。这是 iOS 17 的已知雷区：
///
///   · 隐藏导航栏的页面替换 pop 手势的 delegate 后，从子页滑回、再进入子页，
///     界面冻住；iOS 16 正常，仅 17 复现。
///     developer.apple.com/forums/thread/745986
///   · 同帖解答：「控制器会被带到一个它本不该处理的状态，把**下一次导航操作**
///     的转场搞坏，表现为冻住，直到切到后台再切回来才好。」
///     developer.apple.com/forums/thread/745040
///   · stackoverflow.com/a/77380861 、 davdroman/swiftui-navigation-transitions#100
///
/// 系统原本那份 delegate 还负责「正在转场就不要开始 pop」「bar 正在隐藏」等
/// 边界判断；换成自己那句 `viewControllers.count > 1` 之后，这些保护全丢了。
private class EdgeSwipeBackViewController: UIViewController {
    /// 已经处理过的导航控制器，避免重复设置
    private weak var configuredNav: UINavigationController?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reenablePopGestureIfNeeded()
    }

    private func reenablePopGestureIfNeeded() {
        guard let nav = navigationController else { return }
        // 转场进行中一律不碰导航控制器的状态
        guard nav.transitionCoordinator == nil else { return }
        guard nav.viewControllers.count > 1 else { return }
        guard configuredNav !== nav else { return }
        configuredNav = nav
        nav.interactivePopGestureRecognizer?.isEnabled = true
    }
}
#endif

// MARK: - 2b. 自绘边缘滑动返回（iOS 17 安全版）

extension View {
    /// 自绘的边缘右滑返回。
    ///
    /// 为什么不复用上面的 `.enableEdgeSwipeBack()`：那套要替换系统
    /// `interactivePopGestureRecognizer` 的 delegate，正是它在 iOS 17 上把
    /// 「下一次 push 的转场」搞坏（详见上面的注释与 Apple 论坛链接）。
    ///
    /// 这里完全不碰系统手势识别器：
    ///   · 只在屏幕最左侧 24pt 内起手的拖动才算数；
    ///   · 必须是横向为主（|dx| > 1.5·|dy|）且拖够 60pt；
    ///   · 满足条件就回调一次，由调用方执行 dismiss()。
    ///
    /// 用 simultaneousGesture 挂载，纵向滚动不受影响；也不额外铺一层可命中的
    /// 视图，所以不会像全屏 overlay 那样把按钮点击吃掉。
    func edgeSwipeBack(_ action: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeBackGestureModifier(action: action))
    }
}

private struct EdgeSwipeBackGestureModifier: ViewModifier {
    let action: () -> Void

    /// 防止一次拖动触发多次 dismiss
    @State private var armed = true

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 16, coordinateSpace: .global)
                    .onEnded { value in
                        guard armed else { return }
                        guard value.startLocation.x <= 24 else { return }
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard dx > 60, abs(dx) > abs(dy) * 1.5 else { return }
                        armed = false
                        action()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { armed = true }
                    }
            )
    }
}

// MARK: - 3. View 扩展

extension View {
    /// 启用边缘滑动返回手势 (修复隐藏原生返回按钮后手势失效)
    @ViewBuilder
    func enableEdgeSwipeBack() -> some View {
        #if os(iOS)
        self.modifier(EdgeSwipeBackModifier())
        #else
        self
        #endif
    }
    
    /// 紧凑导航栏修饰符 — 强制 inline 标题 + 隐藏大标题空间
    @ViewBuilder
    func compactNavigationBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
