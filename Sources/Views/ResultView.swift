//
//  ResultView.swift
//  照片转PDF
//
//  生成完成后的结果页：页数 / 体积摘要，分享（系统分享面板）、
//  存储到「文件」（系统文件导出面板），以及完成按钮。
//

import SwiftUI
import UniformTypeIdentifiers

struct ResultView: View {

    let result: GeneratedPDF
    let onDone: () -> Void

    @State private var showShareSheet = false
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
                    showShareSheet = true
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
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)

            Text("分享面板里选「存储到“文件”」可以保存到 iCloud 云盘或本机；选「打印」可以直接打印。")
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
        .sheet(isPresented: $showShareSheet) {
            // iOS 15 没有 .presentationDetents（iOS 16+），交给分享面板自己决定高度
            ShareSheet(items: [result.fileURL])
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
