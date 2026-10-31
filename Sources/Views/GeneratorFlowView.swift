//
//  GeneratorFlowView.swift
//  照片转PDF
//
//  生成过程的一个 sheet：没结果时显示进度（可取消），有结果时切换成结果页。
//  这样避免「进度 sheet 关掉再弹结果 sheet」的层级问题。
//

import SwiftUI

struct GeneratorFlowView: View {

    @ObservedObject var controller: PDFGenerationController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // iOS 15 没有 NavigationStack：用 NavigationView + 栈式导航
        NavigationView {
            Group {
                if let result = controller.result {
                    ResultView(result: result) {
                        dismiss()
                    }
                } else {
                    progressContent
                }
            }
            .navigationTitle(controller.result == nil ? "正在生成" : "生成完成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 注意：这里把 if 放在 ToolbarItem 内部
                ToolbarItem(placement: .cancellationAction) {
                    if controller.result == nil {
                        Button("取消") {
                            controller.cancel()
                            dismiss()
                        }
                    }
                }
            }
        }
        // 用具体类型而不是 .stack 静态成员，确保 iOS 15 SDK 下也能编译
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled(controller.result == nil)
    }

    // MARK: - 进度

    private var progressContent: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "doc.richtext")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.accentColor)

            Text("正在合成 PDF")
                .font(.title3.weight(.semibold))

            Text(controller.totalPages > 0 ? "共 \(controller.totalPages) 页" : "准备中…")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ProgressView(value: min(max(controller.progress, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)

                Text("\(Int((controller.progress * 100).rounded()))%")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            switch controller.phase {
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            case .cancelled:
                Text("已取消")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            default:
                Text("照片较多时需要一点时间，请保持 App 在前台。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(role: .cancel) {
                controller.cancel()
                dismiss()
            } label: {
                Text("取消生成")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        }
    }
}
