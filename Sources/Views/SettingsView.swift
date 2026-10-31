//
//  SettingsView.swift
//  照片转PDF
//
//  页面设置面板：纸张、方向、边距、清晰度、图片质量、文件名。
//  直接绑定 store.options，改完关掉就生效。
//

import SwiftUI

struct SettingsView: View {

    @Binding var options: PDFOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // iOS 15 没有 NavigationStack：用 NavigationView + 栈式导航
        NavigationView {
            Form {
                Section {
                    Picker("页面尺寸", selection: $options.pageSize) {
                        ForEach(PDFOptions.PageSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(options.pageSize.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("页面方向", selection: $options.orientation) {
                        ForEach(PDFOptions.Orientation.allCases) { orientation in
                            Text(orientation.title).tag(orientation)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("页面")
                } footer: {
                    Text("「自动」会按每张照片的长宽比例决定页面大小或方向，横图自动用横向页。")
                }

                Section {
                    Picker("页边距", selection: $options.margin) {
                        ForEach(PDFOptions.MarginPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                } header: {
                    Text("页边距")
                } footer: {
                    Text("页边距是照片四周的白色留白。打印装订建议用「标准」。")
                }

                Section {
                    Picker("清晰度", selection: $options.dpi) {
                        Text("标准 150").tag(150)
                        Text("高清 300").tag(300)
                        Text("超清 450").tag(450)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("图片质量")
                            Spacer()
                            Text("\(Int((options.jpegQuality * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $options.jpegQuality, in: 0.5...1.0, step: 0.05)
                    }
                } header: {
                    Text("画质")
                } footer: {
                    Text("300 DPI 是照片打印的常用标准；文件太大可以降到 150，想更清晰可以调到 450。质量 100% 时保留无损编码，文件会明显变大。")
                }

                Section {
                    TextField("文件名", text: $options.fileName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                } header: {
                    Text("文件名")
                } footer: {
                    Text("最终文件：\(options.pdfFileName)")
                }

                Section {
                    Label("所有处理都在本机完成，照片不会上传到任何服务器。", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("页面设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        // 用具体类型而不是 .stack 静态成员，确保 iOS 15 SDK 下也能编译
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
