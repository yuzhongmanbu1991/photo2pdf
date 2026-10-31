//
//  ShareSheet.swift
//  照片转PDF
//
//  SwiftUI 里调用系统分享面板（UIActivityViewController）的桥接。
//  iOS 16 的 ShareLink 也能分享文件，但直接包一层 UIActivityViewController 更可控。
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 分享内容在创建后不会变化，这里不需要更新
    }
}
