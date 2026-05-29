//
//  DrawingInfo.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/15/26.
//

import Foundation
import SwiftUI
import Combine

struct MetalColors {
    static let red: SIMD4<Float> = SIMD4<Float>(0.7, 0, 0, 1)
    static let yellow: SIMD4<Float> = SIMD4<Float>(1, 1, 0, 1)
    static let blue: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    static let green: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 1)
    static let darkGreen: SIMD4<Float> = SIMD4<Float>(0, 0.5, 0, 1)
    static let black: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    static let white: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
}

enum Mode: Int, Codable {
    case idle
    case creatingCurve
    case editingCurve
}

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
    var hardness: Float?
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
    @Published var lineThickness: Float = 20
    let imageSize: CGSize
    
    // Test properties
    @Published var smoothCurves: Bool = true
    
    @Published var showSmoothingPoints: Bool = false
    @Published var showQuads: Bool = false
    @Published var lineHardness: Float = 1 {
        didSet {
            hardness = pow(2,(2-lineHardness)) - 1
        }
    }
    
    struct BrushSettings: Codable {
        var color: SIMD4<Float>
        var size: Float
        var hardness: Float
    }
    
    @Published var brushSettings: BrushSettings = .init(color: MetalColors.green, size: 10, hardness: 10)
    
    var hardness: Float = 1
    
    @Published var showControlPoints: Bool = true
    
    var curves = [CatmullRomCurve]()
    
    // Items not saved with Codable
    
    @Published var enableDeletePointButton: Bool = false
    
    func setEnableDeletePointButtonState() {
        enableDeletePointButton = drawingMode == .editingCurve &&
        activePointIndex != nil &&
        activeCurveIndex != nil
        
        
    }
    var drawingMode: Mode = .idle {
        didSet {
            setEnableDeletePointButtonState()
        }
    }
    var activeCurveIndex: Int? = nil
    {
        didSet {
            setEnableDeletePointButtonState()
        }
    }
    var activePointIndex: Int? = nil{
        didSet {
            setEnableDeletePointButtonState()
        }
    }
    
    @Published var viewportSize: CGSize = DrawingInfo.defaultSize // The size of the viewport
    
    //    static let defaultSize: CGSize = CGSize(width: 800, height: 300)
    static let defaultSize: CGSize = CGSize(width: 900, height: 600)
    //    static let defaultSize: CGSize = CGSize(width: 1000, height: 250)
    
    var imageAspectRatio: Float {
        return Float(imageSize.width / imageSize.height)
    }
    
    var lastDragLocation: CGPoint? = nil
    var isDragging: Bool = false
    var draggingState: GestureLocation? = nil
    
    /*
     public typealias  pointsArraysTuple = (
       points: [simd_float2],
       tempSmoothedPoints: [simd_float2],
       smoothedPoints: [simd_float2]
     )

     */
    public typealias  metalColorComponents = (
      red: Float,
      green: Float,
      blue: Float,
      alpha : Float)

    var currentColor: Color {
        get {
            let metalColor = currentMetalColor
            return Color(
                red: Double(metalColor[0]),
                green:  Double(metalColor[1]),
                blue:  Double(metalColor[2]),
                opacity: Double(metalColor[3]))
        }
        set {
            var newValueComponents: metalColorComponents
            #if os(macOS)
                let color = NSColor(newValue)
                newValueComponents = (red: Float(color.redComponent),
                                      green: Float(color.greenComponent),
                                      blue: Float(color.blueComponent),
                                      alpha: Float(color.alphaComponent))
            #else
                let uiColor = UIColor(newValue)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                newValueComponents = (red: Float(red),
                                      green: Float(green),
                                      blue: Float(blue),
                                      alpha: Float(alpha))
            #endif
            currentMetalColor = [newValueComponents.red, newValueComponents.green, newValueComponents.blue, newValueComponents.alpha]
        }
    }
    var currentMetalColor: SIMD4<Float>  {
        get {
            if drawingMode == .idle || activeCurveIndex == nil {
                return brushSettings.color
            } else {
                return curves[activeCurveIndex!].color
            }
        }
        set {
            if drawingMode == .idle || activeCurveIndex == nil {
                brushSettings.color = newValue
            } else {
                curves[activeCurveIndex!].color = newValue
            }
        }
    }


    
    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case title
        case text
        case showSmoothingPoints
        case smoothCurves
        case backgroundColor
        case lineThickness
        case lineHardness
        case curves
        case showControlPoints
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.imageSize = DrawingInfo.defaultSize
        self.showSmoothingPoints = try container.decodeIfPresent(Bool.self, forKey: .showSmoothingPoints) ?? false
        self.smoothCurves = try container.decodeIfPresent(Bool.self, forKey: .smoothCurves) ?? true
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
        self.lineThickness = try container.decodeIfPresent(Float.self, forKey: .lineThickness) ?? 5
        self.lineHardness = try container.decodeIfPresent(Float.self, forKey: .lineHardness) ?? 2
        self.showControlPoints = try container.decode(Bool.self, forKey: .showControlPoints)

        self.viewportSize = DrawingInfo.defaultSize

    }
    
    // MARK: - Encode
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showSmoothingPoints, forKey: .showSmoothingPoints)
        try container.encode(smoothCurves, forKey: .smoothCurves)
        try container.encode(CodableColor(color: backgroundColor), forKey: .backgroundColor)
        try container.encode(lineThickness, forKey: .lineThickness)
        try container.encode(lineHardness, forKey: .lineHardness)
        try container.encode(curves, forKey: .curves)
        try container.encode(showControlPoints, forKey: .showControlPoints)
    }
    
    init(title: String, text: String) {
        self.imageSize = DrawingInfo.defaultSize
        self.showSmoothingPoints = false
        self.backgroundColor = .white
        self.viewportSize = DrawingInfo.defaultSize
    }

    // MARK: - Undo

    func registerUndo(with undoManager: UndoManager?) {
        guard let undoManager else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let snapshot = try? encoder.encode(self) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.registerUndo(with: undoManager)
            target.restore(from: snapshot)
        }
    }

    func restore(from data: Data) {
        guard let restored = try? JSONDecoder().decode(DrawingInfo.self, from: data) else { return }
        self.showSmoothingPoints = restored.showSmoothingPoints
        self.smoothCurves = restored.smoothCurves
        self.backgroundColor = restored.backgroundColor
        self.lineThickness = restored.lineThickness
        self.lineHardness = restored.lineHardness
        self.curves = restored.curves
        self.showControlPoints = restored.showControlPoints
        self.drawingMode = .idle
        self.activeCurveIndex = nil
        self.activePointIndex = nil
    }
}
