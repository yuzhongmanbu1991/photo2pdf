//
//  ImageTools.swift
//  照片转PDF
//
//  图片工具：
//    * ImageDecoder  —— 用 ImageIO 生成缩略图 / 读取像素尺寸（不把整张原图解到内存里）
//    * ImageTransformer —— 简单的 90° 旋转（用于网格展示旋转后的缩略图）
//

import ImageIO
import UIKit

enum ImageDecoder {

    /// 读取图片的像素尺寸（已按 EXIF 方向修正，即「看起来的宽高」）
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return pixelSize(of: source)
    }

    /// 读取图片的像素尺寸（已按 EXIF 方向修正）
    static func pixelSize(ofFile url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(of: source)
    }

    private static func pixelSize(of source: CGImageSource) -> CGSize? {
        guard let propertiesRef = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else {
            return nil
        }
        let properties = propertiesRef as NSDictionary
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard width > 0, height > 0 else { return nil }

        // EXIF 方向 5~8 表示画面被旋转了 90°，宽高需要交换
        let exifOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let swapped = (5...8).contains(exifOrientation)
        return swapped
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    /// 从磁盘「降采样」读出一张图：只解码到指定长边，内存占用可控
    /// - Parameters:
    ///   - url: 图片文件路径
    ///   - maxPixelSize: 允许的最大长边像素
    static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    /// 同上的 Data 版本
    static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        return downsampledImage(from: source, maxPixelSize: maxPixelSize)
    }

    static func downsampledImage(from source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let limit = max(64, maxPixelSize.rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // 自动套用 EXIF 方向，出来就是「正的」
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: limit
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum ImageTransformer {

    /// 顺时针旋转若干个 90°。quarters = 1 表示顺时针 90°。
    static func rotate(_ image: UIImage, quarters: Int) -> UIImage {
        let normalized = ((quarters % 4) + 4) % 4
        guard normalized != 0 else { return image }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let targetSize = normalized % 2 == 0
            ? size
            : CGSize(width: size.height, height: size.width)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            // UIGraphicsImageRenderer 的坐标系 y 轴向下，正角度即「视觉上的顺时针」
            cgContext.rotate(by: CGFloat(normalized) * .pi / 2)
            image.draw(in: CGRect(x: -size.width / 2,
                                  y: -size.height / 2,
                                  width: size.width,
                                  height: size.height))
        }
    }
}
