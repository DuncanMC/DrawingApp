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

func simdColorToColor(_ color: simd_float4) -> Color {
        .init(red: Double(color.x),
          green: Double(color.y),
          blue: Double(color.z),
          opacity: Double(color.w))
}
func colorToSimdColor(_ color:  Color) -> simd_float4 {
    let codableColor = CodableColor(color: color)
    return simd_float4(Float(codableColor.red), Float(codableColor.green), Float(codableColor.blue), Float(codableColor.alpha))
}

struct CatmullRomPoint: Codable {
    var coord: simd_float2
    var pointType: PointType
    var hardness: Float
    var pointRadius: Float?
}


struct CatmullRomCurve: Codable {
    var color: simd_float4
    var radius: Float
    var outlineColor: simd_float4?
    var points: [CatmullRomPoint]

    
    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case color
        case radius
        case outlineColor
        case points
    }
    init(
        color: simd_float4,
        radius: Float,
        outlineColor: simd_float4? = nil,
        points: [CatmullRomPoint]
    ) {
        self.color = color
        self.radius = radius
        self.outlineColor = outlineColor
        self.points = points
    }
    
    init(from decoder: Decoder) throws {
        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let codableColor = try container.decodeIfPresent(CodableColor.self, forKey: .color)  else {
                fatalError("no background color found")
            }
            self.color = codableColor.toSimdColor()
            if let codableOutlineColor = try container.decodeIfPresent(CodableColor.self, forKey: .outlineColor)   {
                self.outlineColor = simd_float4( Float(codableOutlineColor.red), Float(codableOutlineColor.green), Float(codableOutlineColor.blue), Float(codableOutlineColor.alpha))
            }
            self.radius = try container.decode(Float.self, forKey: .radius)
            
            if let newPoints = try container.decodeIfPresent([CatmullRomPoint].self, forKey: .points) {
                self.points = newPoints
            } else {
                    self.points = [CatmullRomPoint]()
            }
        } catch {
            print("Error decoding CatmullRomCurve: \(error)")
            throw(error)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(CodableColor(simdColor: self.color), forKey: .color)
        try container.encode(self.radius, forKey: .radius)
        try container.encode(self.points, forKey: .points)
    }
}


final class DrawingInfo: ObservableObject, Codable {
    // Items saved with Codable
    
    @Published var backgroundColor = Color.white
    @Published var linePlacement: Float = 2
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
    
    var lastDragLocation: CGPoint? = nil
    var isDragging: Bool = false
    var draggingState: DragLocations? = nil

    
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
        curves = [
            CatmullRomCurve(
                color: simd_float4(0, 1.0, 0, 1), // green
                radius: 10.0,
                outlineColor: nil,
                points: [
                    CatmullRomPoint(coord: simd_float2(-0.8,  0.8), pointType: .corner, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2(-0.6, -0.8), pointType: .smooth, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2(-0.6,   0), pointType: .smooth, hardness: 1.0, pointRadius: 10.0), //
                    CatmullRomPoint(coord: simd_float2( 0  ,  0.6), pointType: .corner, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2( 0  ,  0.8), pointType: .corner, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2( 0.6, -0.8), pointType: .smooth, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2( 0.8,  0.8), pointType: .corner, hardness: 1.0, pointRadius: 10.0),
                ]
            ),
            CatmullRomCurve(
                color: simd_float4(0.8, 0.0, 0, 1),
                radius: 5,
                outlineColor: nil,
                points: [
                    CatmullRomPoint(coord: simd_float2(-0.4, -0.7), pointType: .corner, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2(-0.4, -0.2), pointType: .smooth, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2( 0.4, -0.7), pointType: .smooth, hardness: 1.0, pointRadius: 10.0),
                    CatmullRomPoint(coord: simd_float2( 0.4, -0.2), pointType: .corner, hardness: 1.0, pointRadius: 10.0),

                ]
            )
            ]

    }
}
