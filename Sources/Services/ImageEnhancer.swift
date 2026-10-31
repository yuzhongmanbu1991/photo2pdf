//
//  ImageEnhancer.swift
//  照片转PDF
//
//  扫描件 / 照片的 Core Image 滤镜（零第三方依赖，只用系统 Core Image）。
//
//  四种模式：
//    * 原图    —— 不做任何处理（最保真）
//    * 增强    —— 提亮阴影 + 加对比 + 略降饱和 + 锐化，尽量接近「全能扫描王」的增强效果
//    * 黑白    —— 去色 + 强对比 + 锐化，模拟复印/黑白扫描件
//    * 灰度    —— 只去色，保留灰阶（适合拍书页但不想丢渐变）
//
//  性能与内存：
//    * CIContext 创建很贵，全局复用一份（CIContext 本身线程安全）；
//    * 滤镜按「一张一张」串行调用，调用方负责降采样与释放，避免多张大图同时进内存；
//    * 使用 CIFilter(name:) + KVC 的老接口（iOS 5 起就有），比 CIFilter.xxx() 工厂方法更稳。
//

import CoreImage
import UIKit

/// 渲染 PDF / 缩略图时使用的滤镜
enum ScanFilter: String, CaseIterable, Identifiable {
    case original
    case enhanced
    case blackWhite
    case grayscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "原图"
        case .enhanced: return "增强"
        case .blackWhite: return "黑白"
        case .grayscale: return "灰度"
        }
    }

    var detail: String {
        switch self {
        case .original: return "保持原样，不处理"
        case .enhanced: return "提亮阴影、加强对比与锐化，最接近扫描 App 的「增强」"
        case .blackWhite: return "去色并加大对比，模拟黑白扫描件"
        case .grayscale: return "只去色，保留灰阶细节"
        }
    }
}

enum ImageEnhancer {

    /// 全局复用的渲染上下文（CIContext 线程安全，可以被多次/多线程调用）
    private static let context = CIContext(options: nil)

    // MARK: - 对外接口

    /// 对 CGImage 应用滤镜（PDF 逐页渲染走这里，避免多一次 UIImage 转换）
    /// - Returns: 处理后的图；滤镜失败时返回 nil，调用方自行决定回退到原图
    static func apply(_ filter: ScanFilter, to image: CGImage) -> CGImage? {
        guard filter != .original else { return image }

        let input = CIImage(cgImage: image)
        let extent = input.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        guard let output = filteredImage(input, filter: filter) else { return nil }

        // 卷积类滤镜理论上保持 extent，这里再裁一次，防止边缘出现无限大区域
        let cropped = output.cropped(to: extent)
        return context.createCGImage(cropped, from: extent)
    }

    /// UIImage 版本（网格缩略图用；尺寸本来就小，转一次开销可忽略）
    static func apply(_ filter: ScanFilter, to image: UIImage) -> UIImage? {
        guard filter != .original else { return image }
        guard let cgImage = image.cgImage else { return image }
        guard let output = apply(filter, to: cgImage) else { return nil }
        // 旋转过的缩略图已经画成了「正方向」，所以 orientation 用 .up
        return UIImage(cgImage: output, scale: image.scale, orientation: .up)
    }

    /// 顺时针旋转若干个 90°（OCR 前把用户手动旋转过的页面摆正）
    /// 用 Core Image 的仿射变换实现，不依赖 UIKit，可以在后台线程安全调用。
    static func rotated(_ image: CGImage, quarters: Int) -> CGImage? {
        let normalized = ((quarters % 4) + 4) % 4
        guard normalized != 0 else { return image }

        let input = CIImage(cgImage: image)
        // CIImage 的坐标系 y 轴向上，所以「视觉上顺时针」对应负角度
        let angle = -CGFloat(normalized) * .pi / 2
        let rotated = input.transformed(by: CGAffineTransform(rotationAngle: angle))
        // 旋转后包围盒原点可能跑到负数区域，平移到 (0,0) 再渲染，避免裁掉内容
        let bounds = rotated.extent
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let translated = rotated.transformed(by: CGAffineTransform(translationX: -bounds.origin.x,
                                                                   y: -bounds.origin.y))
        return context.createCGImage(translated, from: translated.extent)
    }

    // MARK: - 滤镜链

    private static func filteredImage(_ input: CIImage, filter: ScanFilter) -> CIImage? {
        switch filter {
        case .original:
            return input

        case .enhanced:
            // 1) 先提亮阴影（纸张底色发灰时很有用）
            guard let lifted = highlightShadow(input, shadowAmount: 0.55, highlightAmount: 1.0),
                  // 2) 拉对比、抬一点亮度、稍微降饱和
                  let contrast = colorControls(lifted,
                                               contrast: 1.35,
                                               brightness: 0.05,
                                               saturation: 0.90) else {
                return nil
            }
            // 3) 锐化文字边缘
            return unsharpMask(contrast, radius: 1.6, intensity: 0.60)

        case .blackWhite:
            guard let contrast = colorControls(input,
                                               contrast: 1.70,
                                               brightness: 0.06,
                                               saturation: 0.0) else {
                return nil
            }
            return unsharpMask(contrast, radius: 1.6, intensity: 0.80)

        case .grayscale:
            return colorControls(input,
                                 contrast: 1.05,
                                 brightness: 0.0,
                                 saturation: 0.0)
        }
    }

    // MARK: - 具体滤镜（KVC 老接口，兼容性最好）

    private static func colorControls(_ input: CIImage,
                                      contrast: Double,
                                      brightness: Double,
                                      saturation: Double) -> CIImage? {
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        return filter.outputImage
    }

    private static func unsharpMask(_ input: CIImage, radius: Double, intensity: Double) -> CIImage? {
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage
    }

    private static func highlightShadow(_ input: CIImage,
                                        shadowAmount: Double,
                                        highlightAmount: Double) -> CIImage? {
        guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(shadowAmount, forKey: "inputShadowAmount")
        filter.setValue(highlightAmount, forKey: "inputHighlightAmount")
        return filter.outputImage
    }
}
