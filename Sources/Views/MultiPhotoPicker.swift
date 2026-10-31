//
//  MultiPhotoPicker.swift
//  照片转PDF
//
//  iOS 15 兼容的多选相册选择器。
//
//  为什么不用 SwiftUI 的 PhotosPicker？
//    PhotosPicker / PhotosPickerItem 是 iOS 16 才有的 API，本项目最低支持 iOS 15.0
//    （用户真机 iOS 15.1），所以回到 iOS 14 就存在的 PHPickerViewController，
//    用 UIViewControllerRepresentable 桥接一层：
//      * 同样不需要相册权限（PHPicker 是独立进程，只拿到用户勾选的照片）；
//      * 支持多选、HEIC、GIF；
//      * preferredAssetRepresentationMode = .current —— 拿到「当前表示形式」，
//        HEIC 照片就是原始 HEIC，不会被系统悄悄转成 JPEG 掉画质。
//
//  用法（在某个 View 里）：
//      .sheet(isPresented: $showPicker) {
//          MultiPhotoPicker(selectionLimit: 50) { results in
//              showPicker = false
//              Task { await store.addPhotos(from: results) }
//          }
//          .ignoresSafeArea()
//      }
//

import PhotosUI
import SwiftUI

struct MultiPhotoPicker: UIViewControllerRepresentable {

    /// 最多可选多少张（1...；这里由调用方按「还能再加几张」动态传入）
    let selectionLimit: Int

    /// 选择结束的回调：主线程调用；用户点「取消」时 results 为空数组
    let onFinish: ([PHPickerResult]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images                                   // 只要图片（HEIC / JPEG / PNG / GIF）
        configuration.selectionLimit = max(1, selectionLimit)            // 允许多选
        configuration.preferredAssetRepresentationMode = .current        // 保留原始格式，不强制转码
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // 选择器的配置在创建时已经固定，切到前台不需要刷新
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        private let onFinish: ([PHPickerResult]) -> Void
        /// 防止 delegate 被重复调用导致重复导入
        private var finished = false

        init(onFinish: @escaping ([PHPickerResult]) -> Void) {
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            finished = true

            // 先把回调取成局部常量，再切回主线程通知 SwiftUI：关闭 sheet、开始异步导入
            let handler = onFinish
            DispatchQueue.main.async {
                handler(results)
            }
        }
    }
}
