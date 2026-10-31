//
//  PhotoStore.swift
//  照片转PDF
//
//  照片列表的数据源（ObservableObject）：负责
//    * 从系统相册导入照片（PHPicker 返回的 [PHPickerResult]，HEIC / JPEG / PNG 都支持）
//    * 接收相机扫描的页面（VisionKit 拍照 → [UIImage]），和照片走同一条流水线
//    * 把原图落到临时目录，内存里只留小缩略图
//    * 排序（拖动 / 上移下移）、删除、旋转、清空
//    * 按当前滤镜（原图 / 增强 / 黑白 / 灰度）预渲染网格缩略图，串行处理避免内存峰值
//
//  说明：所有方法都由界面在主线程调用；导入/渲染是 async，await 期间不会阻塞界面。
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

    /// 按当前滤镜渲染好的网格缩略图（id -> 图）。滤镜是「原图」时这里为空，直接用 PhotoItem.displayThumbnail
    @Published private(set) var filteredThumbnails: [UUID: UIImage] = [:]

    /// 已经渲染过的滤镜（用来判断需不需要重跑）
    private var thumbnailsFilter: ScanFilter = .original
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

    // MARK: - 导入：相册

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
                                              thumbnail: UIImage(cgImage: thumbnailCG),
                                              origin: .photo))
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
        renderThumbnails(for: newItems)

        if failedCount > 0 {
            errorMessage = "有 \(failedCount) 张照片读取失败，可能是格式不受支持（如 RAW）。"
        }
    }

    // MARK: - 导入：相机扫描

    /// 接收相机扫描的页面（VisionKit 已经做过找边 + 透视校正）
    ///
    /// 扫描页和相册照片走完全相同的流程：JPEG 落盘 → 缩略图 → PhotoItem(origin: .scan)，
    /// 后面的排序/旋转/删除/生成 PDF 都不需要区分来源。
    @MainActor
    func addScannedImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        guard !isImporting else { return }

        isImporting = true
        importProgress = 0
        defer {
            isImporting = false
            importProgress = 0
        }

        // 扫描件的默认排版：页面贴合图像、无边距、默认「增强」滤镜、文件名带时间
        applyScanDefaultsIfNeeded()

        var newItems: [PhotoItem] = []
        var failedCount = 0

        for (index, image) in images.enumerated() {
            if photos.count + newItems.count >= PhotoStore.maxPhotoCount {
                errorMessage = "最多支持 \(PhotoStore.maxPhotoCount) 页，多余的已忽略。"
                break
            }

            // 一页一页处理，每页结束就把中间对象释放掉（扫描页可能是 1200 万像素的大图）
            autoreleasepool {
                // 扫描图本身已经是正方向、且做过透视校正，这里统一存成高质量 JPEG
                guard let data = image.jpegData(compressionQuality: 0.95) else {
                    failedCount += 1
                    return
                }

                let fileURL = workDirectory.appendingPathComponent("scan-\(UUID().uuidString).jpg")
                do {
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    failedCount += 1
                    return
                }

                if let size = ImageDecoder.pixelSize(ofFile: fileURL),
                   let thumbnailCG = ImageDecoder.downsampledImage(at: fileURL,
                                                                  maxPixelSize: PhotoStore.thumbnailPixelSize) {
                    newItems.append(PhotoItem(fileURL: fileURL,
                                              pixelSize: size,
                                              thumbnail: UIImage(cgImage: thumbnailCG),
                                              origin: .scan))
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    failedCount += 1
                }
            }

            importProgress = Double(index + 1) / Double(images.count)
        }

        photos.append(contentsOf: newItems)
        renderThumbnails(for: newItems)

        if failedCount > 0 {
            errorMessage = "有 \(failedCount) 页扫描结果保存失败，请重试。"
        }
    }

    /// 扫描件的默认设置：只在用户还没改过（仍是默认值）时才套用，避免覆盖用户的自定义
    private func applyScanDefaultsIfNeeded() {
        if options.pageSize == .a4 && options.orientation == .auto && options.margin == .standard {
            options.pageSize = .auto       // 页面贴合图像
            options.margin = .none         // 无边距，扫描件铺满整页
        }
        if options.filter == .original {
            options.filter = .enhanced     // 扫描件默认「增强」
        }
        if options.fileName == PDFOptions.defaultFileName {
            options.fileName = PhotoStore.scanFileName()
        }
    }

    /// 生成「扫描_yyyyMMdd_HHmm」形式的默认文件名
    static func scanFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmm"
        return "扫描_" + formatter.string(from: date)
    }

    // MARK: - 滤镜缩略图

    /// 网格里显示用的图：滤镜是原图 / 还没渲染完时，退回未处理的缩略图
    func displayImage(for item: PhotoItem) -> UIImage {
        guard options.filter != .original else { return item.displayThumbnail }
        return filteredThumbnails[item.id] ?? item.displayThumbnail
    }

    /// 滤镜变化后重新渲染缩略图（逐张串行 + 每张之间让出主线程，避免卡界面/内存峰值）
    @MainActor
    func refreshDisplayThumbnails() async {
        let filter = options.filter
        guard filter != thumbnailsFilter else { return }
        thumbnailsFilter = filter

        guard filter != .original else {
            filteredThumbnails = [:]
            return
        }

        var rendered: [UUID: UIImage] = [:]
        for (index, item) in photos.enumerated() {
            if Task.isCancelled { return }
            if let image = ImageEnhancer.apply(filter, to: item.displayThumbnail) {
                rendered[item.id] = image
            }
            // 每 4 张刷新一次界面：既能逐步看到效果，又不会因为频繁发布状态导致掉帧
            if index % 4 == 3 {
                filteredThumbnails = rendered
            }
            await Task.yield()
        }
        filteredThumbnails = rendered
    }

    /// 给新加入的图片补渲染缩略图（当前滤镜不是原图时才需要）
    private func renderThumbnails(for items: [PhotoItem]) {
        let filter = options.filter
        guard filter != .original else { return }
        for item in items {
            if let image = ImageEnhancer.apply(filter, to: item.displayThumbnail) {
                filteredThumbnails[item.id] = image
            }
        }
    }

    // MARK: - 编辑

    /// 顺时针旋转 90°
    func rotate(_ item: PhotoItem) {
        guard let index = photos.firstIndex(of: item) else { return }
        photos[index] = photos[index].rotatingClockwise()

        // 旋转后缩略图变了，滤镜缓存也要跟着更新
        let rotated = photos[index]
        if options.filter != .original {
            if let image = ImageEnhancer.apply(options.filter, to: rotated.displayThumbnail) {
                filteredThumbnails[rotated.id] = image
            }
        }
    }

    /// 删除一张
    func delete(_ item: PhotoItem) {
        guard let index = photos.firstIndex(of: item) else { return }
        let removed = photos.remove(at: index)
        filteredThumbnails.removeValue(forKey: removed.id)
        try? FileManager.default.removeItem(at: removed.fileURL)
    }

    /// 清空全部
    func removeAll() {
        for item in photos {
            try? FileManager.default.removeItem(at: item.fileURL)
        }
        photos.removeAll()
        filteredThumbnails.removeAll()
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
