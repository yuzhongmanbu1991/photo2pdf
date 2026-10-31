//
//  DocumentScannerView.swift
//  照片转PDF
//
//  「扫描」入口：把 VisionKit 的 VNDocumentCameraViewController 包成 SwiftUI 视图。
//
//  系统这个控制器本身就带「自动找边 → 透视校正 → 多页连拍」，效果和全能扫描王很接近，
//  而且零第三方依赖、不需要自己写 OpenCV 那套边缘检测。
//
//  版本说明：
//    * VNDocumentCameraViewController 是 **iOS 13.0** 起（VisionKit 框架），
//      本工程最低 iOS 15.0，所以不需要 #available 分支；
//    * 模拟器不支持（isSupported == false），所以界面里必须先判断再显示「扫描」按钮；
//      真机 iOS 15.1 可以正常使用。
//
//  权限：需要在 Info.plist 声明 NSCameraUsageDescription（见 project.yml），
//        第一次进扫描时会弹系统相机授权框。
//

import AVFoundation
import SwiftUI
import UIKit
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {

    /// 扫描结束：返回每一页的图像（已由系统做好找边/透视校正）
    let onFinish: ([UIImage]) -> Void
    /// 用户点了「取消」
    let onCancel: () -> Void
    /// 相机出错（中文提示）
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
        // 扫描界面由系统维护，不需要更新
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {

        private let parent: DocumentScannerView
        /// 防止 delegate 被重复回调（例如连续点两次保存）
        private var finished = false

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard !finished else { return }
            finished = true

            var images: [UIImage] = []
            if scan.pageCount > 0 {
                for index in 0..<scan.pageCount {
                    images.append(scan.imageOfPage(at: index))
                }
            }

            let handler = parent.onFinish
            DispatchQueue.main.async {
                handler(images)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let handler = parent.onCancel
            DispatchQueue.main.async {
                handler()
            }
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            let handler = parent.onFailure
            let message = "扫描失败：\(error.localizedDescription)"
            DispatchQueue.main.async {
                handler(message)
            }
        }
    }
}

/// 相机扫描的可用性 / 权限判断（界面层只跟这个 enum 打交道，不直接碰 VisionKit）
enum DocumentScanner {

    /// 当前设备是否支持文档扫描（模拟器、无相机设备返回 false）
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    /// 请求相机权限；回调一定在主线程
    static func requestCameraAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async { completion(true) }

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }

        case .denied, .restricted:
            DispatchQueue.main.async { completion(false) }

        @unknown default:
            DispatchQueue.main.async { completion(false) }
        }
    }

    /// 权限被拒时给用户看的中文提示
    static let permissionHint = "没有相机权限。请到「设置 → 照片转 PDF → 相机」里打开，或改用「照片」从相册选择。"

    /// 设备不支持扫描时的中文提示
    static let unsupportedHint = "这台设备不支持相机扫描（模拟器没有相机）。可以用「照片」从相册选择。"
}
