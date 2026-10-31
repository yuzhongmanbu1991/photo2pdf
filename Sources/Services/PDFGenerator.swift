//
//  PDFGenerator.swift
//  照片转PDF
//
//  多页 PDF 合成核心。设计要点（都是为了「大图不爆内存、可取消、可打印」）：
//    1. 先「规划」再「绘制」：只读每张图的元数据算出页面尺寸 / 图片摆放位置，
//       不提前解码图片；
//    2. 绘制时逐页解码：用 ImageIO 直接降采样到「页面所需像素」，画完立刻释放，
//       任何时刻内存里最多只有一页的位图；
//    3. 页面尺寸可变：用 CGPDFContext + 每页独立的 MediaBox，支持「自动」模式
//       （每张照片一个比例的页面），也支持 A4 / Letter 的横竖排版；
//    4. 取消：每一页开始前检查 Task 取消状态，用户点「取消」立刻停；
//    5. 方向：ImageIO 的 kCGImageSourceCreateThumbnailWithTransform 先把 EXIF 摆正，
//       叠加用户手动旋转（旋转在绘制时用 CTM 完成，不额外生成位图）。
//

import CoreGraphics
import Foundation
import ImageIO
import UIKit

// MARK: - 输入 / 输出

/// 生成一页 PDF 所需的照片信息（纯值类型，不持有 UIImage）
struct PDFPhotoSource: Sendable {
    let fileURL: URL
    let pixelSize: CGSize
    let rotation: Int
}

/// 渲染结果
struct PDFRenderResult: Sendable {
    let data: Data
    /// 实际写入的页数（读取失败的照片会被跳过）
    let pageCount: Int
    /// 因为文件读取失败被跳过的照片数量
    let skippedCount: Int
}

enum PDFRendererError: LocalizedError {
    case noPhotos
    case contextUnavailable
    case nothingRendered

    var errorDescription: String? {
        switch self {
        case .noPhotos:
            return "没有可用的照片"
        case .contextUnavailable:
            return "无法创建 PDF 绘图上下文，请重试"
        case .nothingRendered:
            return "所有照片都读取失败，没有生成任何页面"
        }
    }
}

// MARK: - 渲染器

/// 用 actor 包一层，保证绘制过程跑在后台线程（不卡界面），
/// 同时 Task 取消可以自然传递进来。
actor PDFRenderer {

    /// 单页排版方案（内部使用）
    private struct PagePlan {
        let source: PDFPhotoSource
        let pageSize: CGSize
        /// 图片最终绘制的位置（左上角坐标系，单位磅）
        let imageRect: CGRect
        /// 解码时允许的最大长边像素
        let targetPixelSize: CGFloat
    }

    /// 生成 PDF
    /// - Parameters:
    ///   - sources: 照片列表（顺序即页顺序）
    ///   - options: 页面设置
    ///   - progress: 进度回调 0...1，会在后台线程被调用，调用方自行切回主线程
    func render(sources: [PDFPhotoSource],
                options: PDFOptions,
                progress: @Sendable (Double) -> Void) throws -> PDFRenderResult {

        guard !sources.isEmpty else { throw PDFRendererError.noPhotos }

        progress(0.02)

        // 第一步：只算尺寸，不解码
        let plans = sources.map { makePlan(for: $0, options: options) }
        guard let firstPlan = plans.first else { throw PDFRendererError.noPhotos }

        // 第二步：建立 PDF 上下文
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw PDFRendererError.contextUnavailable
        }

        var initialMediaBox = CGRect(origin: .zero, size: firstPlan.pageSize)
        let documentInfo: [CFString: Any] = [
            kCGPDFContextTitle: options.sanitizedFileName,
            kCGPDFContextAuthor: "照片转PDF",
            kCGPDFContextCreator: "照片转PDF (Photo2PDF)"
        ]
        guard let context = CGContext(consumer: consumer,
                                      mediaBox: &initialMediaBox,
                                      documentInfo as CFDictionary) else {
            throw PDFRendererError.contextUnavailable
        }

        var renderedPages = 0
        var skipped = 0
        let total = plans.count

        for (index, plan) in plans.enumerated() {
            // 每一页开始前响应「取消」
            try Task.checkCancellation()

            // 逐页解码；失败就跳过这一页，不影响其它照片
            guard let image = loadPageImage(plan: plan, quality: options.jpegQuality) else {
                skipped += 1
                progress(0.02 + 0.96 * Double(index + 1) / Double(total))
                continue
            }

            // 关键点：每页可以有自己独立的 MediaBox，这样「自动」尺寸才能生效
            let mediaBox = CGRect(origin: .zero, size: plan.pageSize)
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: cgRectData(mediaBox)]
            context.beginPDFPage(pageInfo as CFDictionary)

            // 铺一层白底，避免某些阅读器把透明底显示成黑色
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)

            context.saveGState()
            // CGPDFContext 默认原点在左下角，这里翻转成「左上角原点、y 向下」的坐标，
            // 排版计算和 SwiftUI 保持一致，图片也不会上下颠倒。
            context.translateBy(x: 0, y: plan.pageSize.height)
            context.scaleBy(x: 1, y: -1)

            draw(image: image, in: plan.imageRect, rotation: plan.source.rotation, context: context)

            context.restoreGState()
            context.endPDFPage()

            renderedPages += 1
            progress(0.02 + 0.96 * Double(index + 1) / Double(total))
        }

        context.closePDF()

        guard renderedPages > 0 else { throw PDFRendererError.nothingRendered }

        guard let data = pdfData.copy() as? Data else {
            throw PDFRendererError.contextUnavailable
        }

        progress(1.0)
        return PDFRenderResult(data: data, pageCount: renderedPages, skippedCount: skipped)
    }

    // MARK: - 排版

    /// 计算某一页的页面尺寸与图片位置
    private func makePlan(for source: PDFPhotoSource, options: PDFOptions) -> PagePlan {
        let quarters = ((source.rotation % 4) + 4) % 4
        let quarterTurned = quarters % 2 == 1

        // 手动旋转 90°/270° 时，画面宽高互换
        let displaySize = quarterTurned
            ? CGSize(width: source.pixelSize.height, height: source.pixelSize.width)
            : source.pixelSize

        let aspect: CGFloat = (displaySize.width > 0 && displaySize.height > 0)
            ? displaySize.width / displaySize.height
            : 1.0

        let pageSize = self.pageSize(aspect: aspect, options: options)

        // 内容区 = 页面减去四周留白（留白过大时做个保护，最多占页面 1/3）
        let margin = options.margin.points
        let dx = min(margin, pageSize.width / 3)
        let dy = min(margin, pageSize.height / 3)
        let contentRect = CGRect(origin: .zero, size: pageSize)
            .insetBy(dx: dx, dy: dy)

        // 等比缩放并居中
        let contentAspect = contentRect.width / max(contentRect.height, 1)
        let drawSize: CGSize
        if aspect > contentAspect {
            drawSize = CGSize(width: contentRect.width, height: contentRect.width / aspect)
        } else {
            drawSize = CGSize(width: contentRect.height * aspect, height: contentRect.height)
        }
        let imageRect = CGRect(x: contentRect.midX - drawSize.width / 2,
                               y: contentRect.midY - drawSize.height / 2,
                               width: drawSize.width,
                               height: drawSize.height)

        // 解码尺寸：内容区尺寸（磅）× DPI / 72，再夹在 320...4096 之间
        let contentPoints = max(drawSize.width, drawSize.height)
        let requested = contentPoints * CGFloat(max(options.dpi, 72)) / 72.0
        let sourceLongSide = max(source.pixelSize.width, source.pixelSize.height)
        let capped = min(max(requested, 320), 4096)
        // 不放大：超过原图尺寸没有意义
        let target = sourceLongSide > 0 ? min(capped, sourceLongSide) : capped

        return PagePlan(source: source,
                        pageSize: pageSize,
                        imageRect: imageRect,
                        targetPixelSize: target)
    }

    private func pageSize(aspect: CGFloat, options: PDFOptions) -> CGSize {
        // 分母保护
        let safeAspect = max(min(aspect, 20), 0.05)
        let a4Portrait = CGSize(width: 595.28, height: 841.89)   // 210 × 297 毫米
        let letterPortrait = CGSize(width: 612.0, height: 792.0) // 8.5 × 11 英寸

        switch options.pageSize {
        case .a4:
            return oriented(base: a4Portrait, aspect: safeAspect, orientation: options.orientation)
        case .letter:
            return oriented(base: letterPortrait, aspect: safeAspect, orientation: options.orientation)
        case .auto:
            // 自动：页面比例 = 照片比例，长边取 A4 长边
            let longSide = a4Portrait.height
            let autoSize: CGSize
            if safeAspect >= 1 {
                autoSize = CGSize(width: longSide, height: longSide / safeAspect)
            } else {
                autoSize = CGSize(width: longSide * safeAspect, height: longSide)
            }
            switch options.orientation {
            case .auto:
                return autoSize
            case .portrait:
                return autoSize.width <= autoSize.height
                    ? autoSize
                    : CGSize(width: autoSize.height, height: autoSize.width)
            case .landscape:
                return autoSize.width >= autoSize.height
                    ? autoSize
                    : CGSize(width: autoSize.height, height: autoSize.width)
            }
        }
    }

    /// 固定纸张尺寸下，按方向选项决定横竖；「自动」跟随照片方向
    private func oriented(base: CGSize, aspect: CGFloat, orientation: PDFOptions.Orientation) -> CGSize {
        let shortSide = min(base.width, base.height)
        let longSide = max(base.width, base.height)
        let portrait = CGSize(width: shortSide, height: longSide)
        let landscape = CGSize(width: longSide, height: shortSide)

        switch orientation {
        case .portrait:
            return portrait
        case .landscape:
            return landscape
        case .auto:
            return aspect >= 1 ? landscape : portrait
        }
    }

    // MARK: - 解码 & 绘制

    /// 只解码这一页需要的那点像素，避免整张大图进内存
    private func loadPageImage(plan: PagePlan, quality: Double) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(plan.source.fileURL as CFURL,
                                                      sourceOptions as CFDictionary) else {
            return nil
        }
        guard let decoded = ImageDecoder.downsampledImage(from: source,
                                                          maxPixelSize: plan.targetPixelSize) else {
            return nil
        }

        // 质量 < 1 时重新压成 JPEG：PDF 会以 JPEG 形式内嵌，文件体积明显更小。
        // 质量 = 1 时保留无损编码，画质优先。
        guard quality < 0.999 else { return decoded }

        let image = UIImage(cgImage: decoded)
        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let jpegData = image.jpegData(compressionQuality: CGFloat(quality)),
              let jpegSource = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let recompressed = CGImageSourceCreateImageAtIndex(jpegSource,
                                                                0,
                                                                decodeOptions as CFDictionary) else {
            return decoded
        }
        return recompressed
    }

    /// 在「左上角原点、y 向下」的坐标系里绘制图片，并叠加用户旋转
    private func draw(image: CGImage, in rect: CGRect, rotation: Int, context: CGContext) {
        let quarters = ((rotation % 4) + 4) % 4
        guard quarters != 0 else {
            context.draw(image, in: rect)
            return
        }

        // 旋转 90°/270° 时，需要在旋转后的坐标系里用「交换后的宽高」绘制
        let rawWidth = quarters % 2 == 0 ? rect.width : rect.height
        let rawHeight = quarters % 2 == 0 ? rect.height : rect.width

        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(quarters) * .pi / 2)
        context.draw(image, in: CGRect(x: -rawWidth / 2,
                                       y: -rawHeight / 2,
                                       width: rawWidth,
                                       height: rawHeight))
        context.restoreGState()
    }

    /// 把 CGRect 转成 CGPDFContext 需要的 CFData（MediaBox 的官方类型）
    private func cgRectData(_ rect: CGRect) -> CFData {
        var value = rect
        let data = withUnsafeBytes(of: &value) { buffer in
            Data(buffer)
        }
        return data as CFData
    }
}
