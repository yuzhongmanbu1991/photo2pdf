//
//  PhotoFileImporter.swift
//  照片转PDF
//
//  把 PHPicker 选中的照片落成磁盘文件（iOS 15 没有 PhotosPickerItem，只能自己搬文件）。
//
//  两条路径：
//    1. loadFileRepresentation（首选）：PHPicker 直接给一个临时文件 URL，
//       我们在回调内把它复制到自己的目录 —— 不经过内存，HEIC 原始数据不被转码；
//       注意：这个临时 URL 只在回调执行期间有效，回调返回后就失效了。
//    2. loadDataRepresentation（兜底）：拿 Data 再写盘，兼容只提供数据表示的 provider。
//
//  所有回调都在后台线程，完成后用 CheckedContinuation 交回 async 调用方。
//

import Foundation
import PhotosUI
import UniformTypeIdentifiers

enum PhotoFileImportError: LocalizedError {
    case noImageProvider
    case emptyImageData

    var errorDescription: String? {
        switch self {
        case .noImageProvider:
            return "这张照片没有可用的图片数据"
        case .emptyImageData:
            return "这张照片的数据是空的"
        }
    }
}

enum PhotoFileImporter {

    /// 把一张 PHPicker 结果写进指定目录，返回落地后的文件 URL
    /// - Parameters:
    ///   - result: PHPicker 返回的结果
    ///   - directory: 目标目录（App 的临时工作目录）
    static func copyImage(from result: PHPickerResult,
                          into directory: URL) async throws -> URL {
        let provider = result.itemProvider
        let typeIdentifier = imageTypeIdentifier(for: provider)

        // 优先走「文件表示」：内存友好，且保留原始编码
        do {
            return try await loadFileRepresentation(provider: provider,
                                                    typeIdentifier: typeIdentifier,
                                                    directory: directory)
        } catch {
            // 失败再走「数据表示」
            return try await loadDataRepresentation(provider: provider,
                                                    typeIdentifier: typeIdentifier,
                                                    directory: directory)
        }
    }

    // MARK: - 类型判断

    /// 优先拿「原始格式」的类型标识：HEIC 照片就是 public.heic，不会被先要成 JPEG
    private static let preferredTypeIdentifiers = [
        "public.heic",   // HEIC（iPhone 默认格式）
        "public.jpeg",   // JPEG
        "public.png",    // PNG
        "public.gif",    // GIF
        "public.tiff"    // TIFF
    ]

    /// 在 provider 注册的类型里挑一个「图片」类型
    private static func imageTypeIdentifier(for provider: NSItemProvider) -> String {
        for identifier in preferredTypeIdentifiers
        where provider.hasItemConformingToTypeIdentifier(identifier) {
            return identifier
        }
        // 兜底：任意一个属于 public.image 的具体类型
        for identifier in provider.registeredTypeIdentifiers {
            if let type = UTType(identifier), type.conforms(to: .image) {
                return identifier
            }
        }
        return UTType.image.identifier
    }

    // MARK: - 两条加载路径

    private static func loadFileRepresentation(provider: NSItemProvider,
                                               typeIdentifier: String,
                                               directory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let gate = ContinuationGate()
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                // provider 的回调契约只调用一次，这里再兜一层，避免 continuation 被二次 resume 崩溃
                guard gate.claim() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: PhotoFileImportError.noImageProvider)
                    return
                }

                // 该临时 URL 只在本次回调内有效，必须立刻复制走
                do {
                    let destination = destinationURL(in: directory)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadDataRepresentation(provider: NSItemProvider,
                                               typeIdentifier: String,
                                               directory: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let gate = ContinuationGate()
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                guard gate.claim() else { return }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: PhotoFileImportError.emptyImageData)
                    return
                }

                do {
                    let destination = destinationURL(in: directory)
                    try data.write(to: destination, options: .atomic)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 小工具

    /// 统一用 .img 后缀：ImageIO 是按文件内容识别格式的，不依赖扩展名
    private static func destinationURL(in directory: URL) -> URL {
        directory.appendingPathComponent("photo-\(UUID().uuidString).img")
    }
}

/// 保证 Continuation 只被 resume 一次（多一次就会崩，宁可丢掉后到的回调）
private final class ContinuationGate: @unchecked Sendable {

    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
