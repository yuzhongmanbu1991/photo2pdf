//
//  PhotoItem.swift
//  照片转PDF
//
//  一张已经导入的照片：只保存「磁盘上的原图路径 + 缩略图」，不在内存里长期持有原图，
//  这样选几十张照片也不会把手机内存吃光（真正的原图在生成 PDF 时逐张读取、逐张释放）。
//

import UIKit

/// 图片来自哪里：相册选的照片 / 相机扫描的扫描件
enum PhotoOrigin: String {
    case photo
    case scan

    var title: String {
        self == .scan ? "扫描件" : "照片"
    }
}

/// 网格里展示的一张照片
struct PhotoItem: Identifiable, Equatable {

    /// 稳定唯一标识，用于 SwiftUI 列表 / 拖动排序
    let id: UUID

    /// 照片原始数据在临时目录中的路径（保留了原始编码，HEIC 也不会掉画质）
    let fileURL: URL

    /// 按 EXIF 方向修正之后的像素尺寸
    let pixelSize: CGSize

    /// 用于网格展示的小图（长边约 480 像素）
    let thumbnail: UIImage

    /// 按用户旋转角度旋转后的展示图（缓存，避免每次刷新都重绘）
    private(set) var displayThumbnail: UIImage

    /// 用户旋转了多少个 90°（0...3，顺时针）
    private(set) var rotation: Int

    /// 来源：相册 or 相机扫描（只用于界面标记，不影响 PDF 逻辑）
    let origin: PhotoOrigin

    init(id: UUID = UUID(),
         fileURL: URL,
         pixelSize: CGSize,
         thumbnail: UIImage,
         rotation: Int = 0,
         origin: PhotoOrigin = .photo) {
        self.id = id
        self.fileURL = fileURL
        self.pixelSize = pixelSize
        self.thumbnail = thumbnail
        self.rotation = ((rotation % 4) + 4) % 4
        self.origin = origin
        self.displayThumbnail = ImageTransformer.rotate(thumbnail, quarters: self.rotation)
    }

    /// 生成 PDF 只需要这几个「纯值」，不携带 UIImage，方便在后台线程安全使用
    var source: PDFPhotoSource {
        PDFPhotoSource(fileURL: fileURL, pixelSize: pixelSize, rotation: rotation)
    }

    /// 顺时针旋转 90°，返回一张新的 PhotoItem（struct，值语义）
    func rotatingClockwise() -> PhotoItem {
        var copy = self
        let next = (rotation + 1) % 4
        copy.rotation = next
        copy.displayThumbnail = ImageTransformer.rotate(thumbnail, quarters: next)
        return copy
    }

    /// 是否处于「横向旋转」状态（旋转了 90° 或 270°）
    var isQuarterTurned: Bool { rotation % 2 == 1 }

    // 拖动排序只需要比 id（同一张照片的其它属性变化不应该影响身份）
    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }
}
