//
//  OCRController.swift
//  照片转PDF
//
//  「识别文字」的流程控制：
//    * OCRRunner（actor）在后台线程逐页解码 → 套用当前滤镜 → Vision 识别，串行处理避免内存峰值；
//    * OCRController 暴露进度 / 取消 / 结果，界面直接订阅；
//    * 与 PDF 生成保持同一套写法（Task + is CancellationError + MainActor 更新 UI）。
//
//  识别精度优先：每页降采样到长边 2400px（再大 Vision 也不会明显更准，但会慢很多）。
//

import CoreGraphics
import Foundation

final class OCRController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case running
        case finished
        case cancelled
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var pages: [String] = []
    @Published private(set) var totalPages: Int = 0

    /// 保存最近一次的输入，方便「重试」
    private var lastSources: [PDFPhotoSource] = []
    private var lastOptions: PDFOptions = PDFOptions()
    private var workTask: Task<Void, Never>?

    /// 把每页文字拼成一段可复制文本（空页会被跳过，并标出页码）
    var combinedText: String {
        var blocks: [String] = []
        for (index, text) in pages.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            blocks.append("【第 \(index + 1) 页】\n\(trimmed)")
        }
        return blocks.joined(separator: "\n\n")
    }

    var hasAnyText: Bool {
        !combinedText.isEmpty
    }

    var isRunning: Bool {
        phase == .running
    }

    // MARK: - 控制

    func start(sources: [PDFPhotoSource], options: PDFOptions) {
        guard !sources.isEmpty, workTask == nil else { return }
        lastSources = sources
        lastOptions = options

        phase = .running
        progress = 0
        pages = []
        totalPages = sources.count

        workTask = Task { [weak self] in
            do {
                let runner = OCRRunner()
                let texts = try await runner.run(sources: sources,
                                                 filter: options.filter) { value in
                    Task { @MainActor in
                        self?.progress = value
                    }
                }
                await MainActor.run {
                    self?.pages = texts
                    self?.progress = 1
                    self?.phase = .finished
                    self?.workTask = nil
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

    /// 重试（失败/取消后用同样的输入再跑一次）
    func retry() {
        guard !lastSources.isEmpty else { return }
        workTask?.cancel()
        workTask = nil
        start(sources: lastSources, options: lastOptions)
    }

    func cancel() {
        workTask?.cancel()
    }

    func reset() {
        workTask?.cancel()
        workTask = nil
        phase = .idle
        progress = 0
        pages = []
        totalPages = 0
    }
}

// MARK: - 真正的识别执行者

/// 用 actor 保证识别在后台执行器上跑（不卡界面），同时能收到 Task 取消
actor OCRRunner {

    /// 逐页识别，返回与输入顺序一致的文本数组
    func run(sources: [PDFPhotoSource],
             filter: ScanFilter,
             progress: @Sendable (Double) -> Void) throws -> [String] {
        guard !sources.isEmpty else { return [] }

        var texts: [String] = []
        let total = sources.count

        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()

            // 1) 降采样解码（OCR 不需要原始大图，2400px 足够）
            guard let decoded = ImageDecoder.downsampledImage(at: source.fileURL,
                                                              maxPixelSize: 2400) else {
                texts.append("")
                progress(Double(index + 1) / Double(total))
                continue
            }

            // 2) 套用用户当前选择的滤镜（黑白/增强通常更利于识别）
            let filtered: CGImage
            if filter == .original {
                filtered = decoded
            } else {
                filtered = ImageEnhancer.apply(filter, to: decoded) ?? decoded
            }

            // 3) 用户手动旋转过的页面先摆正，再识别
            let upright = ImageEnhancer.rotated(filtered, quarters: source.rotation) ?? filtered

            try Task.checkCancellation()

            // 4) Vision 识别（失败就把这一页当空文本，不影响其它页）
            let text = (try? TextRecognizer.recognize(image: upright)) ?? ""
            texts.append(text)

            progress(Double(index + 1) / Double(total))
        }

        return texts
    }
}
