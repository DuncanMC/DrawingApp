//
//  DrawingInfo.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/15/26.
//

import Foundation
import SwiftUI
import Combine

enum PointType: Int, Codable {
    case smooth
    case corner
}

struct CatmullRomPoint: Codable {
    var coord: simd_float2
    var pointType: PointType
    var hardness: Float
    var radius: Float
}


struct CatmullRomCurve: Codable {
    var color: Color
    var outlineColor: Color?
    let points: [CatmullRomPoint]

    
    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case color
        case outlineColor
        case points
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let codableColor = try container.decodeIfPresent(CodableColor.self, forKey: .color)  else {
            fatalError("no background color found")
        }
        self.color = codableColor.toColor()
        guard let codableOutlineColor = try container.decodeIfPresent(CodableColor.self, forKey: .outlineColor)  else {
            fatalError("no background color found")
        }
        self.outlineColor = codableOutlineColor.toColor()

        self.points = try container.decode([CatmullRomPoint].self, forKey: .points)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CodableColor(color: self.color), forKey: .color)
        try container.encode(self.points, forKey: .points)
    }
}


final class DrawingInfo: ObservableObject, Codable {
    // Items saved with Codable
    
    @Published var backgroundColor = Color.white
    @Published var linePlacement: Float = 0
    let imageSize: CGSize
    
    // Test properties
    @Published var title: String
    @Published var text: String
    @Published var toggleIsOn: Bool = false
    
    var showControlPoints: Bool = true
    
    var curves = [CatmullRomCurve]()
    
    // Items not saved with Codable
    
    @Published var viewportSize: CGSize = DrawingInfo.defaultSize // The size of the viewport
    
    var cancellables = Set<AnyCancellable>()
    //    static let defaultSize: CGSize = CGSize(width: 800, height: 300)
    static let defaultSize: CGSize = CGSize(width: 900, height: 600)
    //    static let defaultSize: CGSize = CGSize(width: 1000, height: 250)
    
    var imageAspectRatio: Float {
        return Float(imageSize.width / imageSize.height)
    }
    
    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case title
        case text
        case toggleIsOn
        case backgroundColor
        case linePlacement
        case curves
        case showControlPoints
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.imageSize = DrawingInfo.defaultSize
        self.title = try container.decode(String.self, forKey: .title)
        self.text = try container.decode(String.self, forKey: .text)
        self.toggleIsOn = try container.decodeIfPresent(Bool.self, forKey: .toggleIsOn) ?? false
        if let curves = try container.decodeIfPresent([CatmullRomCurve].self, forKey: .curves) {
            self.curves = curves
        } else {
            self.curves = [CatmullRomCurve]()
        }
        if let codableColor = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor) {
            self.backgroundColor = codableColor.toColor()
        } else {
            self.backgroundColor = .white
        }
        self.linePlacement = try container.decodeIfPresent(Float.self, forKey: .linePlacement) ?? 0
        self.showControlPoints = try container.decode(Bool.self, forKey: .showControlPoints)

        self.viewportSize = DrawingInfo.defaultSize

        doInitSetup()
    }
    
    // MARK: - Encode
    func encode(to encoder: Encoder) throws {
        print("Encoding '\(text)'")
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(text, forKey: .text)
        try container.encode(toggleIsOn, forKey: .toggleIsOn)
        try container.encode(CodableColor(color: backgroundColor), forKey: .backgroundColor)
        try container.encode(linePlacement, forKey: .linePlacement)
        try container.encode(curves, forKey: .curves)
        try container.encode(showControlPoints, forKey: .showControlPoints)
    }
    
    init(title: String, text: String) {
        self.imageSize = DrawingInfo.defaultSize
        self.title = title
        self.text = text
        self.toggleIsOn = false
        self.backgroundColor = .white
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
