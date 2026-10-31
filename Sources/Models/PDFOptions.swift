//
//  PDFOptions.swift
//  照片转PDF
//
//  页面设置：页面尺寸、方向、页边距、图片质量、清晰度（DPI）、文件名。
//  全部是纯值类型，直接绑定到 SwiftUI 的 Form 上。
//

import CoreGraphics
import Foundation

struct PDFOptions: Equatable {

    // MARK: - 页面尺寸

    enum PageSize: String, CaseIterable, Identifiable {
        case a4
        case letter
        case auto

        var id: String { rawValue }

        var title: String {
            switch self {
            case .a4: return "A4"
            case .letter: return "Letter"
            case .auto: return "自动"
            }
        }

        var detail: String {
            switch self {
            case .a4: return "210 × 297 毫米"
            case .letter: return "8.5 × 11 英寸"
            case .auto: return "按照片比例"
            }
        }
    }

    // MARK: - 页面方向

    enum Orientation: String, CaseIterable, Identifiable {
        case portrait
        case landscape
        case auto

        var id: String { rawValue }

        var title: String {
            switch self {
            case .portrait: return "纵向"
            case .landscape: return "横向"
            case .auto: return "自动"
            }
        }
    }

    // MARK: - 页边距

    enum MarginPreset: String, CaseIterable, Identifiable {
        case none
        case small
        case standard
        case large

        var id: String { rawValue }

        /// 四周留白的磅值（1 磅 = 1/72 英寸）
        var points: CGFloat {
            switch self {
            case .none: return 0
            case .small: return 18
            case .standard: return 36
            case .large: return 54
            }
        }

        var title: String {
            switch self {
            case .none: return "无边距"
            case .small: return "小（6 毫米）"
            case .standard: return "标准（13 毫米）"
            case .large: return "大（19 毫米）"
            }
        }
    }

    // MARK: - 可调参数

    var pageSize: PageSize = .a4
    var orientation: Orientation = .auto
    var margin: MarginPreset = .standard

    /// JPEG 压缩质量 0.5...1.0（1.0 表示不重新压缩，文件最大、画质最好）
    var jpegQuality: Double = 0.8

    /// 目标清晰度，单位 DPI。300 是照片打印的常用标准
    var dpi: Int = 300

    /// 输出文件名（不含 .pdf 后缀的清理在 sanitizedFileName 里做）
    var fileName: String = "我的照片"

    // MARK: - 派生信息

    /// 去掉非法字符之后的文件名（不含扩展名）
    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = fileName.components(separatedBy: invalid).joined()
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "我的照片" : trimmed
    }

    /// 导出时使用的完整文件名
    var pdfFileName: String {
        sanitizedFileName + ".pdf"
    }

    /// 底部状态栏用的一行摘要
    var summaryText: String {
        "\(pageSize.title) · \(orientation.title) · \(dpi) DPI"
    }
}
