//
//  ContentView.swift
//  照片转PDF
//
//  主界面：照片网格 + 排序/旋转/删除 + 底部生成按钮。
//  照片选择用系统 PHPicker（iOS 14+ API，iOS 15 可用的 MultiPhotoPicker 桥接），
//  不需要相册权限，也不会读到你不想给的照片。
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @EnvironmentObject private var store: PhotoStore
    @StateObject private var generator = PDFGenerationController()

    /// 是否正在显示相册选择器（PHPicker）
    @State private var showPicker = false
    /// 正在拖动的那张（用于拖动排序）
    @State private var draggingItem: PhotoItem?

    @State private var showSettings = false
    @State private var showGenerator = false
    @State private var showClearConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 168), spacing: 12)]

    /// 还能再加几张（选择器的多选上限跟着这个走）
    private var remainingSlots: Int {
        max(PhotoStore.maxPhotoCount - store.photos.count, 0)
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
            .sheet(isPresented: $showSettings) {
                SettingsView(options: $store.options)
            }
            .sheet(isPresented: $showGenerator, onDismiss: {
                generator.reset()
            }) {
                GeneratorFlowView(controller: generator)
            }
            .sheet(isPresented: $showPicker) {
                // PHPicker 自带界面：全屏铺开，选完（或取消）回调里关掉 sheet
                MultiPhotoPicker(selectionLimit: remainingSlots) { results in
                    showPicker = false
                    guard !results.isEmpty else { return }
                    Task { await store.addPhotos(from: results) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog("清空所有照片？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) { store.removeAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清空后需要重新选择照片。")
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
        }
        // 用具体类型而不是 .stack 静态成员，确保 iOS 15 SDK 下也能编译
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if store.photos.isEmpty {
            EmptyStateView(onPick: { showPicker = true })
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
            Text("长按缩略图可拖动排序，点右下角旋转，点右上角删除")
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
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("页面设置")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showPicker = true
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
                        showSettings = true
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
        showGenerator = true
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
