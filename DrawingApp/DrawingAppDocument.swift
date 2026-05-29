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

final class DrawingAppDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    var drawingInfo: DrawingInfo

    static var readableContentTypes: [UTType] = [.drawingDocument]

    init() {
        self.drawingInfo = DrawingInfo(title: "Untitled", text: "")
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.drawingInfo = try JSONDecoder().decode(DrawingInfo.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(drawingInfo)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
