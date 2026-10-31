//
//  PhotoGridCell.swift
//  照片转PDF
//
//  九宫格里的一格：缩略图 + 序号 + 删除按钮 + 旋转按钮，
//  长按弹出菜单（旋转 / 上移 / 下移 / 删除）。
//

import SwiftUI

struct PhotoGridCell: View {

    let item: PhotoItem
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
                Image(uiImage: item.displayThumbnail)
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
            .accessibilityLabel("第 \(index + 1) 张照片")
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
        .accessibilityLabel("删除第 \(index + 1) 张照片")
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
        .accessibilityLabel("旋转第 \(index + 1) 张照片")
    }
}
