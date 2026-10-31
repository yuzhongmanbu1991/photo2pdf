//
//  PDFFileDocument.swift
//  照片转PDF
//
//  「存储到“文件”」需要的 FileDocument 包装：把生成好的 PDF Data 交给系统的文件导出面板。
//

import SwiftUI
import UniformTypeIdentifiers

struct PDFFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
