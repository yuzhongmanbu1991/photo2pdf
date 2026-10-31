//
//  PhotoGridCell.swift
//  照片转PDF
//
//  九宫格里的一格：缩略图 + 序号（+ 扫描件标记）+ 删除按钮 + 旋转按钮，
//  长按弹出菜单（旋转 / 上移 / 下移 / 删除）。
//
//  缩略图由外部传入（PhotoStore.displayImage(for:)），这样切换滤镜时整格会跟着换图，
//  本视图不关心图片是相册照片还是相机扫描件。
//

import SwiftUI
import UIKit

struct PhotoGridCell: View {

    let item: PhotoItem
    /// 已经按当前滤镜渲染好的缩略图
    let image: UIImage
    let index: Int
    let isFirst: Bool
    let isLast: Bool

    let onRotate: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    private let corner: CGFloat = 14

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) { indexBadge }
            .overlay(alignment: .topTrailing) { deleteButton }
            .overlay(alignment: .bottomTrailing) { rotateButton }
            .overlay(alignment: .bottomLeading) { originBadge }
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contextMenu {
                Button {
                    onRotate()
                } label: {
                    Label("旋转 90°", systemImage: "rotate.right")
                }
                Button {
                    onMoveUp()
                } label: {
                    Label("前移", systemImage: "arrow.left")
                }
                .disabled(isFirst)
                Button {
                    onMoveDown()
                } label: {
                    Label("后移", systemImage: "arrow.right")
                }
                .disabled(isLast)
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("第 \(index + 1) 张\(item.origin.title)")
    }

    // MARK: - 覆盖层

    private var indexBadge: some View {
        Text("\(index + 1)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(6)
    }

    /// 扫描件在左下角标一个小相机，方便区分来源（不影响 PDF）
    @ViewBuilder
    private var originBadge: some View {
        if item.origin == .scan {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    private var deleteButton: some View {
        Button {
            onDelete()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel("删除第 \(index + 1) 张")
    }

    private var rotateButton: some View {
        Button {
            onRotate()
        } label: {
            Image(systemName: "rotate.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel("旋转第 \(index + 1) 张")
    }
}
