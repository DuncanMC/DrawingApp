//
//  DrawingAppDocument.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

extension UTType {
    static let drawingDocument: UTType = UTType(exportedAs: "com.wareto.drawingDocument")
}

final class DrawingInfo: ObservableObject, Codable {
//    let objectWillChange: ObservableObjectPublisher
    
    
    // Items saved with Codable
    let imageSize: CGSize
    @Published var title: String
    @Published var text: String
    @Published var toggleIsOn: Bool = false
    @Published var backgroundColor = Color.white
    @Published var texAspect: Float = 1.0
    @Published var linePlacement: Float = 0
    
    


    // Items not saved with Codable
    
    var cancellables = Set<AnyCancellable>()
//    static let defaultSize: CGSize = CGSize(width: 800, height: 300)
    static let defaultSize: CGSize = CGSize(width: 800, height: 800)
//    static let defaultSize: CGSize = CGSize(width: 1000, height: 250)

    var imageAspectRatio: Float {
        return Float(imageSize.width / imageSize.height)
    }
    @Published var viewportSize: CGSize = DrawingInfo.defaultSize // The size of the viewport

    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case title
        case text
        case toggleIsOn
        case backgroundColor
        case texAspect
        case linePlacement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.imageSize = DrawingInfo.defaultSize
        self.title = try container.decode(String.self, forKey: .title)
        self.text = try container.decode(String.self, forKey: .text)
        self.toggleIsOn = try container.decodeIfPresent(Bool.self, forKey: .toggleIsOn) ?? false
        if let codableColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) {
            self.backgroundColor = codableColor.toColor()
        } else {
            self.backgroundColor = .white
        }
        self.texAspect = try container.decodeIfPresent(Float.self, forKey: .texAspect) ?? 1.0
//        self.linePlacement = try container.decodeIfPresent(Float.self, forKey: .linePlacement) ?? 0
        self.linePlacement =  0
        self.viewportSize = DrawingInfo.defaultSize
        doInitSetup()
    }
    
    // MARK: - Encode
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(toggleIsOn, forKey: .toggleIsOn)
        try container.encode(CodableColor(color: backgroundColor), forKey: .backgroundColor)
        try container.encode(texAspect, forKey: .texAspect)
        try container.encode(linePlacement, forKey: .linePlacement)
    }
    
    init(title: String, text: String) {
        self.imageSize = DrawingInfo.defaultSize
        self.title = title
        self.text = text
        self.toggleIsOn = false
        self.backgroundColor = .white
        self.texAspect = 1.0
        self.linePlacement = 0
        self.viewportSize = DrawingInfo.defaultSize
        doInitSetup()
    }
    func doInitSetup() {
        objectWillChange.sink { _ in
            #if os(macOS)
            let documentController: NSDocumentController = .shared
            if let document = documentController.currentDocument {
                document.updateChangeCount(.changeDone)
              }
            #endif
        }
        .store(in: &cancellables)
    }
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

