//
//  PhotoStore.swift
//  照片转PDF
//
//  照片列表的数据源（ObservableObject）：负责
//    * 从系统相册导入照片（PHPicker 返回的 [PHPickerResult]，HEIC / JPEG / PNG 都支持）
//    * 把原图落到临时目录，内存里只留小缩略图
//    * 排序（拖动 / 上移下移）、删除、旋转、清空
//
//  说明：所有方法都由界面在主线程调用；导入是 async，await 期间不会阻塞界面。
//

import Foundation
import PhotosUI
import UIKit

final class PhotoStore: ObservableObject {

    /// 一次最多导入多少张（每一页一张照片，太多会明显变慢）
    static let maxPhotoCount = 60
    /// 缩略图长边像素（网格单元约 110pt，480 足够清晰又省内存）
    static let thumbnailPixelSize: CGFloat = 480

    @Published private(set) var photos: [PhotoItem] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: Double = 0
    /// 页面设置，直接绑定到设置面板
    @Published var options = PDFOptions()
    /// 出问题时给用户看的中文提示（设置为非 nil 时界面弹 alert）
    @Published var errorMessage: String?

    /// 原图落盘的目录（每次启动清空，避免临时文件越攒越多）
    private let workDirectory: URL

    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Photo2PDF-Sources", isDirectory: true)
        workDirectory = base
        // 上次运行残留的临时文件直接清掉（App 不保存上一次的选择）
        try? FileManager.default.removeItem(at: base)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: - 导入

    /// 从 PHPicker 的选择结果导入照片
    ///
    /// 流程：PHPicker 已经把用户选中的照片以「临时文件 / 数据」的形式给了我们，
    /// 这里逐张复制到 App 自己的临时目录，并只解出一张小缩略图放进内存。
    @MainActor
    func addPhotos(from results: [PHPickerResult]) async {
        guard !results.isEmpty else { return }
        guard !isImporting else { return }

        isImporting = true
        importProgress = 0
        defer {
            isImporting = false
            importProgress = 0
        }

        var newItems: [PhotoItem] = []
        var failedCount = 0

        for (index, result) in results.enumerated() {
            if photos.count + newItems.count >= PhotoStore.maxPhotoCount {
                errorMessage = "最多支持 \(PhotoStore.maxPhotoCount) 张照片，多余的已忽略。"
                break
            }

            do {
                // 1) 把原图（HEIC 保持 HEIC）复制到临时目录，后续生成 PDF 时逐张读取
                let fileURL = try await PhotoFileImporter.copyImage(from: result, into: workDirectory)

                // 2) 读像素尺寸 + 只解出一张小缩略图放内存
                if let size = ImageDecoder.pixelSize(ofFile: fileURL),
                   let thumbnailCG = ImageDecoder.downsampledImage(at: fileURL,
                                                                  maxPixelSize: PhotoStore.thumbnailPixelSize) {
                    newItems.append(PhotoItem(fileURL: fileURL,
                                              pixelSize: size,
                                              thumbnail: UIImage(cgImage: thumbnailCG)))
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    failedCount += 1
                }
            } catch {
                failedCount += 1
            }

            importProgress = Double(index + 1) / Double(results.count)
        }

        photos.append(contentsOf: newItems)

        if failedCount > 0 {
            errorMessage = "有 \(failedCount) 张照片读取失败，可能是格式不受支持（如 RAW）。"
        }
    }

    // MARK: - 编辑

    /// 顺时针旋转 90°
    func rotate(_ item: PhotoItem) {
        guard let index = photos.firstIndex(of: item) else { return }
        photos[index] = photos[index].rotatingClockwise()
    }

    /// 删除一张
    func delete(_ item: PhotoItem) {
        guard let index = photos.firstIndex(of: item) else { return }
        let removed = photos.remove(at: index)
        try? FileManager.default.removeItem(at: removed.fileURL)
    }

    /// 清空全部
    func removeAll() {
        for item in photos {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        photos.removeAll()
    }

    /// 上移 / 下移（offset = -1 上移，+1 下移），越界自动忽略
    func move(_ item: PhotoItem, by offset: Int) {
        guard let from = photos.firstIndex(of: item) else { return }
        let to = from + offset
        guard to >= 0, to < photos.count else { return }
        photos.swapAt(from, to)
    }

    /// 拖动排序：把 from 位置移动到 to 位置
    func move(from: Int, to: Int) {
        guard from != to,
              photos.indices.contains(from),
              photos.indices.contains(to) else { return }
        let item = photos.remove(at: from)
        photos.insert(item, at: to)
    }
}
