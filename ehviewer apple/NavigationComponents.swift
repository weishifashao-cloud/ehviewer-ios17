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
#if os(iOS)
struct EdgeSwipeBackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(EdgeSwipeBackHelper())
    }
}

/// UIKit 辅助视图 — 查找最近的 UINavigationController，必要时把 pop 手势重新打开
private struct EdgeSwipeBackHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        EdgeSwipeBackViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

/// 只做一件事：系统把 interactivePopGestureRecognizer 关掉了，就把它重新打开。
///
/// ⚠️ 这里绝对不能再改它的 delegate。
///
/// 原实现做了两件危险的事：
///   1. 把 `interactivePopGestureRecognizer.delegate` 换成了 UINavigationController
///      自己，并给它加了一个**全局**的 `UIGestureRecognizerDelegate` 扩展，
///      于是整个进程里所有 UINavigationController 的 `gestureRecognizerShouldBegin`
///      都变成一句 `viewControllers.count > 1`。系统原本那份 delegate 还负责
///      「正在转场就不要再开始 pop」「bar 正在隐藏中」这些边界判断，换成自己之后
///      这些全没了。
///   2. 把「刷新手势」放在 `viewDidLayoutSubviews` 里 —— 也就是每一次布局都会去碰
///      一次导航控制器。
///
/// 两者叠加的后果正好落在「从画廊详情 push 到全部预览/评论」这一刻：转场进行中
/// 布局反复触发，pop 手势在转场期间被重新配置，UIKit 的转场状态机被搅乱，
/// push 停在半路、整屏不再接收触摸 —— 就是「点了没跳过去、界面动不了」。
///
/// 现在改成：只在 viewDidAppear 里、且没有任何转场进行时，把 isEnabled 置回 true。
private class EdgeSwipeBackViewController: UIViewController {
    /// 已经处理过的导航控制器，避免重复设置
    private weak var configuredNav: UINavigationController?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reenablePopGestureIfNeeded()
    }

    private func reenablePopGestureIfNeeded() {
        guard let nav = navigationController else { return }
        // 转场进行中不要碰导航控制器的状态
        guard nav.transitionCoordinator == nil else { return }
        guard nav.viewControllers.count > 1 else { return }
        guard configuredNav !== nav else { return }
        configuredNav = nav
        nav.interactivePopGestureRecognizer?.isEnabled = true
    }
}
#endif

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
