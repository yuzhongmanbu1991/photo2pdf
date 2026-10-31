//
//  EmptyStateView.swift
//  照片转PDF
//
//  还没加内容时的引导页：说明用途 + 两个入口（相机扫描 / 相册照片）+ 使用提示。
//
//  iOS 15 兼容：不用 PhotosPicker（iOS 16+），改成普通 Button + 回调，
//  由 ContentView 统一弹出 MultiPhotoPicker（PHPicker）或 VisionKit 扫描界面。
//

import SwiftUI

struct EmptyStateView: View {

    /// 点「扫描」时回调（打开相机扫描）
    let onScan: () -> Void
    /// 点「选择照片」时回调（打开相册选择器）
    let onPick: () -> Void
    /// 当前设备是否支持相机扫描（模拟器没有相机，为 false）
    let showsScanButton: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.05)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 148, height: 148)
                    Image(systemName: showsScanButton ? "viewfinder" : "photo.on.rectangle.angled")
                        .font(.system(size: 62, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    Text("扫描 / 照片 转 PDF")
                        .font(.title2.weight(.semibold))
                    Text("拍纸质文档（自动找边、透视校正），或从相册选照片，\n调整顺序和方向后一键生成可打印、可分享的 PDF。\n全部在你的手机上完成，不会上传任何内容。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                VStack(spacing: 10) {
                    if showsScanButton {
                        Button {
                            onScan()
                        } label: {
                            Label("扫描文档", systemImage: "camera.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        pickButton
                            .buttonStyle(.bordered)
                    } else {
                        pickButton
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 36)

                VStack(alignment: .leading, spacing: 12) {
                    tipRow(icon: "camera.viewfinder", text: "扫描时支持多页连拍，系统会自动找边并校正透视")
                    tipRow(icon: "wand.and.stars", text: "左上角设置里可以选「增强 / 黑白」滤镜，扫描件默认增强")
                    tipRow(icon: "textformat", text: "生成 PDF 后还能「识别文字」，一键复制全部文字")
                    tipRow(icon: "hand.tap", text: "长按缩略图可以拖动排序，右下角旋转，右上角删除")
                }
                .padding(.top, 4)
                .padding(.horizontal, 36)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 子视图

    private var pickButton: some View {
        Button {
            onPick()
        } label: {
            Label("从相册选择照片", systemImage: "photo.on.rectangle")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
