//
//  ContentView.swift
//  照片转PDF
//
//  主界面：照片网格 + 排序/旋转/删除 + 底部生成按钮。
//  两个入口并列：
//    * 「扫描」——相机拍纸质文档（VisionKit，真机可用，自动找边 + 透视校正）
//    * 「照片」——从相册多选（PHPicker，不需要相册权限）
//  两者导入后都进入同一套网格 / 排序 / 旋转 / 生成 PDF 流程。
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @EnvironmentObject private var store: PhotoStore
    @StateObject private var generator = PDFGenerationController()

    /// 当前要弹出的面板（用一个 enum 统一管理，避免同一视图挂多个 .sheet 在 iOS 15 上互相抢占）
    private enum ActiveSheet: Int, Identifiable {
        case settings
        case generator
        case picker

        var id: Int { rawValue }
    }

    @State private var activeSheet: ActiveSheet?
    /// 是否正在显示相机扫描（VisionKit）
    @State private var showScanner = false
    /// 正在拖动的那张（用于拖动排序）
    @State private var draggingItem: PhotoItem?

    @State private var showClearConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 168), spacing: 12)]

    /// 还能再加几张（选择器的多选上限跟着这个走）
    private var remainingSlots: Int {
        max(PhotoStore.maxPhotoCount - store.photos.count, 0)
    }

    /// 当前设备能不能用相机扫描（模拟器为 false）
    private var scannerAvailable: Bool {
        DocumentScanner.isSupported
    }

    var body: some View {
        // iOS 15 没有 NavigationStack，用 NavigationView + 强制栈式导航（iPad 上也是单栏）
        NavigationView {
            ZStack {
                backgroundGradient
                content
            }
            .navigationTitle("照片转 PDF")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $activeSheet, onDismiss: {
                // 生成流程关闭后复位状态机（其它面板关闭时也会走这里，复位是幂等的）
                if generator.result != nil || generator.phase != .idle {
                    generator.reset()
                }
            }) { sheet in
                switch sheet {
                case .settings:
                    SettingsView(options: $store.options)

                case .generator:
                    GeneratorFlowView(controller: generator)

                case .picker:
                    // PHPicker 自带界面：全屏铺开，选完（或取消）回调里关掉 sheet
                    MultiPhotoPicker(selectionLimit: remainingSlots) { results in
                        activeSheet = nil
                        guard !results.isEmpty else { return }
                        Task { await store.addPhotos(from: results) }
                    }
                    .ignoresSafeArea()
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                // VisionKit 的扫描界面：自动找边、透视校正、多页连拍
                DocumentScannerView(onFinish: { images in
                    showScanner = false
                    guard !images.isEmpty else { return }
                    Task { await store.addScannedImages(images) }
                }, onCancel: {
                    showScanner = false
                }, onFailure: { message in
                    showScanner = false
                    store.errorMessage = message
                })
                .ignoresSafeArea()
            }
            .confirmationDialog("清空所有内容？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.removeAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清空后需要重新扫描或选择照片。")
            }
            .alert("提示", isPresented: errorBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
            .overlay {
                if store.isImporting {
                    ImportingOverlay(progress: store.importProgress)
                }
            }
            // 滤镜变化时重新渲染网格缩略图（串行处理，避免卡顿/内存峰值）
            .task(id: store.options.filter) {
                await store.refreshDisplayThumbnails()
            }
        }
        // 用具体类型而不是 .stack 静态成员，确保 iOS 15 SDK 下也能编译
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if store.photos.isEmpty {
            EmptyStateView(onScan: { startScan() },
                           onPick: { activeSheet = .picker },
                           showsScanButton: scannerAvailable)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    hintBar
                    LazyVGrid(columns: columns, spacing: 12) {
                        // 用 PhotoItem 自身做 id（Identifiable），序号在格子内部按当前数组位置计算，
                        // 这样删除/排序后序号会自动重排。
                        ForEach(store.photos) { item in
                            let index = store.photos.firstIndex(of: item) ?? 0
                            PhotoGridCell(item: item,
                                          image: store.displayImage(for: item),
                                          index: index,
                                          isFirst: index == 0,
                                          isLast: index == store.photos.count - 1,
                                          onRotate: { withAnimation(.easeInOut(duration: 0.18)) { store.rotate(item) } },
                                          onDelete: { withAnimation { store.delete(item) } },
                                          onMoveUp: { withAnimation { store.move(item, by: -1) } },
                                          onMoveDown: { withAnimation { store.move(item, by: 1) } })
                                .onDrag {
                                    draggingItem = item
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(of: [UTType.text],
                                        delegate: PhotoDropDelegate(item: item,
                                                                    store: store,
                                                                    draggingItem: $draggingItem))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var hintBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
            Text("长按缩略图可拖动排序，点右下角旋转，点右上角删除；右上角相机可继续扫描")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private var backgroundGradient: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.14), Color.clear],
                       startPoint: .top,
                       endPoint: .center)
            .ignoresSafeArea()
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("页面设置")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            // 相机扫描（模拟器不支持，此时只显示「+ 照片」）
            if scannerAvailable {
                Button {
                    startScan()
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .accessibilityLabel("扫描文档")
                .disabled(remainingSlots <= 0 || store.isImporting)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                activeSheet = .picker
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("添加照片")
            .disabled(remainingSlots <= 0)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if !store.photos.isEmpty {
                Menu {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Label("页面设置", systemImage: "slider.horizontal.3")
                    }
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空所有照片", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多")
            }
        }
    }

    // MARK: - 底部操作条

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(store.photos.isEmpty ? "还没有选择照片" : "共 \(store.photos.count) 张照片")
                Text("·")
                Text(store.options.summaryText)
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Button {
                startGeneration()
            } label: {
                Label("生成 PDF", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.photos.isEmpty || store.isImporting)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - 动作

    private func startGeneration() {
        guard !store.photos.isEmpty else { return }
        let sources = store.photos.map { $0.source }
        let options = store.options
        generator.start(sources: sources, options: options)
        activeSheet = .generator
    }

    /// 打开相机扫描（先判断设备支持 + 相机权限）
    private func startScan() {
        guard DocumentScanner.isSupported else {
            store.errorMessage = DocumentScanner.unsupportedHint
            return
        }
        DocumentScanner.requestCameraAccess { granted in
            if granted {
                showScanner = true
            } else {
                store.errorMessage = DocumentScanner.permissionHint
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { newValue in
                if !newValue { store.errorMessage = nil }
            }
        )
    }
}

// MARK: - 拖动排序

/// 拖动排序的 DropDelegate：
/// 拖到某一格上方时，直接把被拖动的照片移动到这一格的位置。
struct PhotoDropDelegate: DropDelegate {

    let item: PhotoItem
    let store: PhotoStore
    @Binding var draggingItem: PhotoItem?

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem,
              dragging.id != item.id,
              let from = store.photos.firstIndex(of: dragging),
              let to = store.photos.firstIndex(of: item) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.move(from: from, to: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}

// MARK: - 导入进度遮罩

private struct ImportingOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                Text(progress > 0 ? "正在读取照片 \(Int(progress * 100))%" : "正在准备…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
    }
}
