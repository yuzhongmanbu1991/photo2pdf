//
//  OCRSheetView.swift
//  照片转PDF
//
//  「识别文字」面板：
//    * 识别中：进度条 + 取消
//    * 完成：可选中复制的文字 + 「复制全部」
//    * 没有识别到 / 失败：给提示和重试
//
//  OCR 不写入 PDF（v2.0 只把文字给用户复制），后续 v2.1 可以做成不可见的文字层。
//

import SwiftUI
import UIKit

struct OCRSheetView: View {

    @ObservedObject var controller: OCRController
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false

    var body: some View {
        NavigationView {
            Group {
                if controller.phase == .finished {
                    finishedContent
                } else {
                    progressContent
                }
            }
            .navigationTitle("识别文字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onDisappear {
            // 面板关掉时停止还在跑的识别任务
            controller.cancel()
        }
    }

    // MARK: - 识别完成

    private var finishedContent: some View {
        VStack(spacing: 0) {
            if controller.hasAnyText {
                ScrollView {
                    Text(controller.combinedText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text("没有识别到文字")
                        .font(.headline)
                    Text("可以试试：换用「黑白 / 增强」滤镜、把照片拍正、或提高清晰度后重新生成。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            VStack(spacing: 8) {
                Button {
                    copyAll()
                } label: {
                    Label(copied ? "已复制" : "复制全部",
                          systemImage: copied ? "checkmark.circle" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!controller.hasAnyText)

                Text("共 \(controller.pages.count) 页 · OCR 结果不会写进 PDF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 识别中 / 失败

    private var progressContent: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50, weight: .light))
                .foregroundStyle(Color.accentColor)

            Text("正在识别文字")
                .font(.title3.weight(.semibold))

            Text("共 \(controller.totalPages) 页 · 简体中文 + 英文")
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

            if let message = statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isFailed ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("页数较多时需要一点时间，请保持 App 在前台。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            HStack(spacing: 12) {
                if controller.phase == .running {
                    Button(role: .cancel) {
                        controller.cancel()
                        dismiss()
                    } label: {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button {
                        controller.retry()
                    } label: {
                        Text("重试")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        dismiss()
                    } label: {
                        Text("关闭")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 状态文案

    /// 失败信息 / 「已取消」，没有就返回 nil（显示默认提示）
    private var statusMessage: String? {
        switch controller.phase {
        case .failed(let message):
            return message
        case .cancelled:
            return "已取消"
        default:
            return nil
        }
    }

    private var isFailed: Bool {
        switch controller.phase {
        case .failed:
            return true
        default:
            return false
        }
    }

    // MARK: - 动作

    private func copyAll() {
        let text = controller.combinedText
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
