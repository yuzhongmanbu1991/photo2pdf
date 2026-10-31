//
//  ResultView.swift
//  照片转PDF
//
//  生成完成后的结果页：页数 / 体积摘要，分享（系统分享面板）、
//  存储到「文件」（系统文件导出面板）、识别文字（OCR），以及完成按钮。
//

import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {

    let result: GeneratedPDF
    let onDone: () -> Void

    @StateObject private var ocr = OCRController()

    /// 用一个 enum 统一管理弹层，避免同一视图挂多个 .sheet 在 iOS 15 上互相抢占
    private enum ActiveSheet: Int, Identifiable {
        case share
        case ocr

        var id: Int { rawValue }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var showFileExporter = false
    @State private var exportMessage: String?
    @State private var showExportAlert = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 128, height: 128)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 66, weight: .regular))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text("PDF 已生成")
                    .font(.title3.weight(.semibold))
                Text(result.suggestedFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                infoChip(icon: "doc.on.doc", text: "\(result.pageCount) 页")
                infoChip(icon: "internaldrive", text: result.byteCountText)
            }

            if result.skippedCount > 0 {
                Text("有 \(result.skippedCount) 张照片读取失败，已跳过。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 12) {
                Button {
                    activeSheet = .share
                } label: {
                    Label("分享 / 存储到「文件」", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    showFileExporter = true
                } label: {
                    Label("存储到「文件」", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    startOCR()
                } label: {
                    Label("识别文字（OCR）", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)

            Text("分享面板里选「存储到“文件”」可以保存到 iCloud 云盘或本机；选「打印」可以直接打印。识别出的文字可一键复制，v2.0 暂不写入 PDF。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button("完成") {
                onDone()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.bottom, 8)
        }
        .sheet(item: $activeSheet, onDismiss: {
            // OCR 面板关闭后复位（取消/完成后都回到 idle）
            if !ocr.isRunning { ocr.reset() }
        }) { sheet in
            switch sheet {
            case .share:
                // iOS 15 没有 .presentationDetents（iOS 16+），交给分享面板自己决定高度
                ShareSheet(items: [result.fileURL])
            case .ocr:
                OCRSheetView(controller: ocr)
            }
        }
        .fileExporter(isPresented: $showFileExporter,
                      document: PDFFileDocument(data: result.data),
                      contentType: .pdf,
                      defaultFilename: result.suggestedFileName) { exportResult in
            switch exportResult {
            case .success:
                exportMessage = "已保存到「文件」。"
            case .failure(let error):
                exportMessage = "保存失败：\(error.localizedDescription)"
            }
            showExportAlert = true
        }
        .alert("提示", isPresented: $showExportAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    // MARK: - 动作

    /// 对生成这份 PDF 的所有页面做 OCR（识别文字）
    private func startOCR() {
        ocr.start(sources: result.sources, options: result.options)
        activeSheet = .ocr
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
    }
}
