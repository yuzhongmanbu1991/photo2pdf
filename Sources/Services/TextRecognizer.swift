//
//  TextRecognizer.swift
//  照片转PDF
//
//  用系统 Vision 做文字识别（OCR）。
//
//  版本：VNRecognizeTextRequest 是 iOS 13.0 起就有的 API，本工程最低 iOS 15.0，
//        不需要 #available 分支，可以直接用。
//  语言：优先简体中文 + 英文（Vision 用 BCP-47 标签：zh-Hans / en-US）。
//        个别系统版本如果报「语言不支持」，会自动退回纯英文再试一次，
//        保证 OCR 至少能出结果、而不是直接报错。
//
//  注意：v2.0 只把文字给用户看/复制，不往 PDF 里写文字层（留给 v2.1）。
//

import CoreGraphics
import Foundation
import Vision

enum TextRecognizer {

    /// 识别文字时优先使用的语言（Vision 用 BCP-47 标签）
    static let preferredLanguages = ["zh-Hans", "en-US"]

    /// 对一张图做文字识别，返回按行拼接的文本（识别不到时返回空字符串）
    static func recognize(image: CGImage) throws -> String {
        try recognize(image: image, languages: preferredLanguages)
    }

    // MARK: - 内部

    private static func recognize(image: CGImage, languages: [String]) throws -> String {
        // 每次都新建 request：Vision 的 request 不适合复用（尤其是并发场景）
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate          // 精确模式（比 .fast 慢，但扫描件效果明显更好）
        request.usesLanguageCorrection = true         // 开启语言校正，中文断行更自然
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // 有的系统版本不支持中文识别语言：退回纯英文再试一次
            if languages != ["en-US"] {
                return try recognize(image: image, languages: ["en-US"])
            }
            throw error
        }

        let observations = request.results ?? []
        let lines = observations.compactMap { observation -> String? in
            observation.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }
}
