//
//  DrawingAppDocument.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

extension UTType {
    static let drawingDocument: UTType = UTType(exportedAs: "com.wareto.drawingDocument")
}



struct DrawingAppDocument {

    var drawingInfo: DrawingInfo
    
    init(drawingInfo: DrawingInfo = DrawingInfo(title: "Untitled", text: "")) {
        self.drawingInfo = drawingInfo
    }
}

extension DrawingAppDocument: FileDocument {
    
    static let writableContentTypes: [UTType] = [.drawingDocument]
    
    nonisolated static var readableContentTypes: [UTType] { [.drawingDocument] }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let info = try JSONDecoder().decode(DrawingInfo.self, from: data)
        self.drawingInfo = info
    }
    
    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(drawingInfo)
        return .init(regularFileWithContents: data)
    }
}

