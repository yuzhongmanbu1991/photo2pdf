//
//  Photo2PDFApp.swift
//  照片转PDF
//
//  App 入口：只做一件事 —— 注入 PhotoStore 和主题色。
//

import SwiftUI

@main
struct Photo2PDFApp: App {

    /// 全局唯一的照片仓库，导入后的照片在 App 生命周期内一直保留
    @StateObject private var store = PhotoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Color.accentColor)
        }
    }
}
