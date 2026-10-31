//
//  EmptyStateView.swift
//  照片转PDF
//
//  还没选照片时的引导页：一句话说明用途 + 直接选照片的按钮 + 三条使用提示。
//
//  iOS 15 兼容：按钮不再用 PhotosPicker（iOS 16+），改成普通 Button + 回调，
//  由 ContentView 统一弹出 MultiPhotoPicker（PHPicker）。
//

import SwiftUI

struct EmptyStateView: View {

    /// 点「选择照片」时回调（打开相册选择器）
    let onPick: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.05)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .frame(width: 148, height: 148)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 62, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 8) {
                    Text("把照片变成 PDF")
                        .font(.title2.weight(.semibold))
                    Text("选几张照片，调整顺序和方向，一键生成可以打印、可以分享的 PDF。\n全部在你的手机上完成，不会上传任何照片。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)

                Button {
                    onPick()
                } label: {
                    Label("选择照片", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 12) {
                    tipRow(icon: "hand.tap", text: "长按缩略图可以拖动排序")
                    tipRow(icon: "rotate.right", text: "点缩略图右下角可以旋转 90°")
                    tipRow(icon: "slider.horizontal.3", text: "左上角可以设置纸张、方向、边距和清晰度")
                }
                .padding(.top, 6)
                .padding(.horizontal, 40)

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
