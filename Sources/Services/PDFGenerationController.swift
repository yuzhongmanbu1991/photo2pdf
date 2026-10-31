//
//  PDFGenerationController.swift
//  照片转PDF
//
//  把「点一下生成 PDF」这件事拆成可观察的状态机：
//    idle -> rendering(进度) -> finished(带结果) / cancelled / failed
//  这样界面上只需要订阅 phase / progress / result 即可，不用自己管 Task 生命周期。
//

import Foundation

/// 生成好的 PDF（同时持有 Data，方便「存储到文件」直接写盘）
struct GeneratedPDF: Identifiable {
    let id = UUID()
    let fileURL: URL
    let data: Data
    let pageCount: Int
    let skippedCount: Int
    let suggestedFileName: String
    let createdAt: Date

    var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

final class PDFGenerationController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case rendering
        case finished
        case cancelled
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var totalPages: Int = 0
    @Published private(set) var result: GeneratedPDF?

    private var workTask: Task<Void, Never>?

    var isBusy: Bool {
        phase == .rendering
    }

    /// 开始生成
    func start(sources: [PDFPhotoSource], options: PDFOptions) {
        guard !sources.isEmpty, workTask == nil else { return }

        phase = .rendering
        progress = 0
        totalPages = sources.count
        result = nil

        workTask = Task { [weak self] in
            do {
                let renderResult = try await PDFGenerator.generate(sources: sources,
                                                                   options: options) { value in
                    Task { @MainActor in
                        self?.progress = value
                    }
                }
                await MainActor.run {
                    self?.finish(renderResult: renderResult, options: options)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.phase = .cancelled
                    self?.workTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.phase = .failed(error.localizedDescription)
                    self?.workTask = nil
                }
            }
        }
    }

    /// 取消生成
    func cancel() {
        workTask?.cancel()
    }

    /// 关闭界面时复位
    func reset() {
        workTask?.cancel()
        workTask = nil
        phase = .idle
        progress = 0
        totalPages = 0
        result = nil
    }

    /// 清掉结果（分享面板关闭后不需要立刻清，留给用户自己关）
    func clearResult() {
        result = nil
    }

    // MARK: - 内部

    private func finish(renderResult: PDFRenderResult, options: PDFOptions) {
        defer { workTask = nil }

        // 写到临时目录，供「分享」和「文件」使用
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Photo2PDF-Output", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(options.pdfFileName)

        do {
            try renderResult.data.write(to: fileURL, options: .atomic)
        } catch {
            phase = .failed("PDF 写入临时文件失败：\(error.localizedDescription)")
            return
        }

        result = GeneratedPDF(fileURL: fileURL,
                              data: renderResult.data,
                              pageCount: renderResult.pageCount,
                              skippedCount: renderResult.skippedCount,
                              suggestedFileName: options.pdfFileName,
                              createdAt: Date())
        progress = 1
        phase = .finished
    }
}

// MARK: - 真正的生成入口

enum PDFGenerator {

    /// 异步生成 PDF，内部通过 PDFRenderer（actor）在后台线程绘制
    static func generate(sources: [PDFPhotoSource],
                         options: PDFOptions,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> PDFRenderResult {
        let renderer = PDFRenderer()
        return try await renderer.render(sources: sources,
                                         options: options,
                                         progress: progress)
    }
}
