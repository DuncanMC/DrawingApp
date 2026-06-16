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
    static let brightRed: SIMD4<Float> = SIMD4<Float>(1, 0, 0, 1)
    static let pink: SIMD4<Float> = SIMD4<Float>(1, 0.3, 0.3, 1)
    static let yellow: SIMD4<Float> = SIMD4<Float>(1, 1, 0, 1)
    static let blue: SIMD4<Float> = SIMD4<Float>(0, 0, 1, 1)
    static let green: SIMD4<Float> = SIMD4<Float>(0, 1, 0, 1)
    static let darkGreen: SIMD4<Float> = SIMD4<Float>(0, 0.5, 0, 1)
    static let black: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)
    static let white: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
}

enum TransformHandle: String {
    case topLeft
    case topMiddle
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomMiddle
    case bottomRight
    case transformRect
    case rotationCenter
    case outside
}
struct DragHandle {
    var coord: simd_float2
    let handleType: TransformHandle
}
struct TransformModeValues {
    var rotationPoint: simd_float2
    var topLeft: simd_float2
    var topRight: simd_float2
    var bottomLeft: simd_float2
    var bottomRight: simd_float2
    var selectedTransformHandle: TransformHandle? = nil
    var dragHandles: [DragHandle]
    var transformRectCenter: simd_float2 {
        let diagonalOne = equationForLine(from: topLeft, to: bottomRight)
        let diagonalTwo = equationForLine(from: topRight, to: bottomLeft)
        return intersection(line1: diagonalOne, line2: diagonalTwo) ?? .zero
    }
    var topMiddle: simd_float2 {
        (topLeft + topRight) / 2
    }
    var middleLeft: simd_float2 {
        (topLeft + bottomLeft) / 2
    }
    var middleRight: simd_float2 {
        (topRight + bottomRight) / 2
    }
    var bottomMiddle: simd_float2 {
        (bottomLeft + bottomRight) / 2
    }
}


enum Mode: Int, Codable {
    case idle
    case creatingCurve
    case editingCurve
    case selecting
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
    var pointRadius: Float?
}


struct CatmullRomCurve: Codable {
    var color: simd_float4
    var radius: Float
    var outlineColor: simd_float4?
    var points: [CatmullRomPoint]
    var hardness: Float?
    var isClosedCurve: Bool = false

    
    // MARK: - Codable Keys
    enum CodingKeys: String, CodingKey {
        case color
        case radius
        case outlineColor
        case points
        case isClosedCurve
        case hardness
    }
    init(
        color: simd_float4,
        radius: Float,
        outlineColor: simd_float4? = nil,
        isClosedCurve: Bool = false,
        points: [CatmullRomPoint],
        hardness: Float? = nil
    ) {
        self.color = color
        self.radius = radius
        self.outlineColor = outlineColor
        self.isClosedCurve = isClosedCurve
        self.points = points
        self.hardness = hardness
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
            
            if let isClosedCurve = try container.decodeIfPresent(Bool.self, forKey: .isClosedCurve)   {
                self.isClosedCurve = isClosedCurve
            }

            if let hardness = try container.decodeIfPresent(Float.self, forKey: .hardness)   {
                self.hardness = hardness
            }

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
        try container.encode(self.isClosedCurve, forKey: .isClosedCurve)
        try container.encode(self.points, forKey: .points)
        try container.encode(self.hardness, forKey: .hardness)
    }
}

struct SelectedPoint: Hashable {
    let curveIndex: Int
    let pointIndex: Int
}

let minThickness: Float = 2.0
let maxThickness: Float = 120.0

final class DrawingInfo: ObservableObject, Codable {
    // Items saved with Codable
    
    @Published var backgroundColor = Color.white
    //@Published var lineThickness: Float = 20
    let imageSize: CGSize
    
    // Test properties
    @Published var smoothCurves: Bool = true
    
    @Published var showSmoothingPoints: Bool = false
    @Published var showQuads: Bool = false
    
    var squeezeActive: Bool = false {
        didSet {
            if squeezeActive != oldValue {
                print("squeezeActive = \(squeezeActive)")
            }
        }
    }
    
    @Published var inMarqueeSelectionMode: Bool = false
    
    var lineHardnessString: String {
        return String(format: "%.1f", lineHardness * 50)
    }
    // If one or more curves is selected, tie the slider to their value. Otherwise, use brushSettings.lineHardnes.
    var lineHardness: Float {
        get {
            if let curveIndex = selectedPoints.first?.curveIndex {
                return curves[curveIndex].hardness ?? brushSettings.lineHardness
            } else {
                return brushSettings.lineHardness
            }
        }
        set {
            if  !uniqueSelectedCurveIndexes.isEmpty {
                for curveIndex in uniqueSelectedCurveIndexes {
                    curves[curveIndex].hardness = newValue
                }
            }
            brushSettings.lineHardness = newValue
        }
    }
    
    struct BrushSettings: Codable {
        var color: SIMD4<Float>
        var size: Float
        var lineHardness: Float
    }
    
    @Published var brushSettings: BrushSettings = .init(
        color: MetalColors.green,
        size: 10,
        lineHardness: 1
    )
    
//    var hardness: Float = 1 // computed from lineHardness. 1 = linear transition. 0 = max no blending.
    
    @Published var showControlPoints: Bool = true
    @Published var showGridLines: Bool = false

    @Published var curves = [CatmullRomCurve]()
    
    // Items not saved with Codable
    
    @Published var enableDeletePointButton: Bool = false
    
    func handleChangeInSelectedPoints(pointCountChanged: Bool) {
        enableDeletePointButton = drawingMode == .editingCurve &&
        !selectedPoints.isEmpty
        
        if pointCountChanged || drawingMode != .editingCurve {
            transformSelection = false
        }
        
        // Update the properties singleCurveSelectedAndNotFirst and singleCurveSelectedAndNotLast (used to enable/disable menu items
        singleCurveSelectedAndNotLast = {
            guard singleCurveSelected else { return false }
            let firstPoint = selectedPoints.first!
            return firstPoint.curveIndex != curves.count - 1
        }()
        singleCurveSelectedAndNotFirst = {
            guard singleCurveSelected else { return false }
            let firstPoint = selectedPoints.first!
            return firstPoint.curveIndex != 0
        }()
    }
    
    var drawingMode: Mode = .idle {
        didSet {
            if oldValue != drawingMode {
                handleChangeInSelectedPoints(pointCountChanged: false)
            }
        }
    }
    private var _selectedPoints: Set<SelectedPoint> = []
    var selectedPoints: Set<SelectedPoint> {
        set {
            let pointCount = _selectedPoints.count
            let newPointCount = newValue.count
            _selectedPoints = newValue
            handleChangeInSelectedPoints(pointCountChanged: pointCount != newPointCount)
        }
        get {
            return _selectedPoints
        }
    }

    var selectedCurveIsClosed: Bool {
        get {
            guard singleCurveSelected,
                  let selectedPoint = selectedPoints.first else { return false }
            let selectedCurveIndex = selectedPoint.curveIndex
            let selectedCurve = curves[selectedCurveIndex]
            return selectedCurve.isClosedCurve
        }
        set {
            guard singleCurveSelected,
                  let selectedPoint = selectedPoints.first else { return }
            let selectedCurveIndex = selectedPoint.curveIndex
            var selectedCurve = curves[selectedCurveIndex]
            selectedCurve.isClosedCurve = newValue
            curves[selectedCurveIndex] = selectedCurve
        }
    }
    @Published var viewportSize: CGSize = DrawingInfo.defaultSize // The size of the viewport
    
    //    static let defaultSize: CGSize = CGSize(width: 800, height: 300)
    static let defaultSize: CGSize = CGSize(width: 900, height: 600)
    //    static let defaultSize: CGSize = CGSize(width: 1000, height: 250)
    
    var imageAspectRatio: Float {
        return Float(imageSize.width / imageSize.height)
    }
    
    var landscape: Bool { imageAspectRatio > 1}

    
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

    // MARK: computed properties

    var deleteSelectedPointString:String {
        selectedPoints.count == 1 ? "Delete Selected Point" :
        "Delete Selected Points"
    }

    var deleteSelectedCurveString:String {
        singleCurveSelected ? "Delete Selected Curve" :
        "Delete Selected Curves"
    }
    var currentThicknessString: String {
        String(format: "%.1f", currentThickness)
    }
    
    var currentThickness: Float {
        get {
            guard !selectedPoints.isEmpty else { return brushSettings.size }
            let selectedCurveIndex = selectedPoints.first!.curveIndex
            let pointIndex = selectedPoints.first!.pointIndex
            guard curves.count > selectedCurveIndex else {
                return brushSettings.size
            }
            let curve = curves[selectedCurveIndex]
            let point = curve.points[pointIndex]
            return point.pointRadius ?? brushSettings.size
        }
        set {
           if selectedPoints.count == 1 {
                let selectedCurveIndex = selectedPoints.first!.curveIndex
                let pointIndex = selectedPoints.first!.pointIndex
                var curve = curves[selectedCurveIndex]
                var point = curve.points[pointIndex]
                point.pointRadius = newValue
                curve.points[pointIndex] = point
                curves[selectedCurveIndex] = curve
            } else {
                for selectedPoint in selectedPoints {
                    let selectedCurveIndex = selectedPoint.curveIndex
                    let pointIndex = selectedPoint.pointIndex
                    var curve = curves[selectedCurveIndex]
                    var point = curve.points[pointIndex]
                    point.pointRadius = newValue
                    curve.points[pointIndex] = point
                    curves[selectedCurveIndex] = curve
                }
            }
            brushSettings.size = newValue
        }
    }
    var currentColor: Color {
        get {
            let metalColor: SIMD4<Float>
            if singleCurveSelected {
                metalColor = curves[selectedPoints.first!.curveIndex].color
            } else {
                metalColor = currentMetalColor
            }
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
                return brushSettings.color
        }
        set {
            if drawingMode == .idle || selectedPoints.isEmpty {
                brushSettings.color = newValue
            } else {
                var curveIndexes = Set<Int>()
                // Find all the unique curves in teh list of selected points
                for point in selectedPoints {
                    curveIndexes.insert(point.curveIndex)
                }
                // Loop through and change the color of all selected curves
                for index in curveIndexes {
                    var aCurve = curves[index]
                    aCurve.color = newValue
                    curves[index] = aCurve
                }
            }
        }
    }
    @Published var singleCurveSelectedAndNotFirst: Bool = false
    
    @Published var singleCurveSelectedAndNotLast: Bool = false
    
    var singleCurveSelected: Bool {
        if selectedPoints.count == 1 { return true}
        if selectedPoints.count == 0 { return false}
        var selectedPointsArray = Array(selectedPoints)
        let firstPoint = selectedPointsArray.removeFirst()
        let firstCurveIndex = firstPoint.curveIndex
        for aPoint in selectedPointsArray {
            if aPoint.curveIndex != firstCurveIndex {
                return false
            }
        }
        return true
    }
    
    var marqueeSelectionStartPoint: simd_float2? = nil
    var marqueeSelectionEndPoint: simd_float2? = nil

    
    var selectedPointsInfo: (center: simd_float2, size: simd_float2)? {
        if selectedPoints.isEmpty { return nil }
        var minX: Float = Float.infinity
        var maxX: Float = -Float.infinity
        var minY: Float = Float.infinity
        var maxY: Float = -Float.infinity
        for aPoint in selectedPoints {
            let coords: simd_float2 = curves[aPoint.curveIndex].points[aPoint.pointIndex].coord
            if coords.x < minX { minX = coords.x }
            if coords.x > maxX { maxX = coords.x }
            if coords.y < minY { minY = coords.y }
            if coords.y > maxY { maxY = coords.y }
        }
        let topLeft: simd_float2 = simd_float2(x: minX, y: maxY)
        let topRight = simd_float2(x: maxX, y: maxY)
        let bottomRight = simd_float2(x: maxX, y: minY)
        let rotationCenter = simd_float2(x: (topRight.x + topLeft.x) / 2, y: (topRight.y + bottomRight.y) / 2)
        return (rotationCenter, simd_float2(x: topRight.x - topLeft.x, y: topRight.y - bottomRight.y))
    }
    
    @Published var marchingAnts: Bool = true
    @Published var transformSelection: Bool = false {
        didSet {
            guard transformSelection else {
                transformModeValues = nil
                return
            }
             var minX: Float = Float.infinity
             var maxX: Float = -Float.infinity
             var minY: Float = Float.infinity
             var maxY: Float = -Float.infinity
            let aspect = imageAspectRatio
            let landscape = aspect > 1
            let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/aspect) : simd_float2(1*aspect, 1)

             for aPoint in selectedPoints {
                 let coords: simd_float2 = curves[aPoint.curveIndex].points[aPoint.pointIndex].coord
                 if coords.x < minX { minX = coords.x }
                 if coords.x > maxX { maxX = coords.x }
                 if coords.y < minY { minY = coords.y }
                 if coords.y > maxY { maxY = coords.y }
             }
             let border = 40 * metalWidthPerPixel
             let buffer = 10 * metalWidthPerPixel
             if minX - border / adjustment.x > -1 + buffer / adjustment.x { minX -= border / adjustment.x }
             
             if minY - border / adjustment.y > -1 + buffer / adjustment.y { minY -= border / adjustment.y }
             
             if maxX + border / adjustment.x < 1 - buffer / adjustment.x { maxX += border / adjustment.x }
             
             if maxY + border / adjustment.y < 1 - buffer / adjustment.y { maxY += border / adjustment.y }
             
            let topLeft: simd_float2 = simd_float2(x: minX, y: maxY)
            let topRight = simd_float2(x: maxX, y: maxY)
            let bottomLeft = simd_float2(x: minX, y: minY)
            let bottomRight = simd_float2(x: maxX, y: minY)
            let rotationCenter = simd_float2(x: (topRight.x + topLeft.x) / 2, y: (topRight.y + bottomRight.y) / 2)
            let middleX = (topLeft.x + bottomRight.x) / 2.0
            let middleY = (topLeft.y + bottomRight.y) / 2.0

            let topMiddle = simd_float2(x: middleX, y: topLeft.y)
            let bottomMiddle = simd_float2(x: middleX, y: bottomRight.y)
            let middleLeft = simd_float2(x: topLeft.x, y: middleY)
            let middleRight = simd_float2(x: topRight.x, y: middleY)
            let dragHandles = [
                DragHandle(coord: topLeft, handleType: .topLeft),
                DragHandle(coord: topMiddle, handleType: .topMiddle),
                DragHandle(coord: topRight, handleType: .topRight),
                DragHandle(coord: middleLeft, handleType: .middleLeft),
                DragHandle(coord: middleRight, handleType: .middleRight),
                DragHandle(coord: bottomLeft, handleType: .bottomLeft),
                DragHandle(coord: bottomMiddle, handleType: .bottomMiddle),
                DragHandle(coord: bottomRight, handleType: .bottomRight),
            ]
            
            transformModeValues = TransformModeValues(
                rotationPoint: rotationCenter,
                topLeft: topLeft,
                topRight: topRight,
                bottomLeft: bottomLeft,
                bottomRight: bottomRight,
                dragHandles: dragHandles)
        }
    }
    @Published var texture: MTLTexture?

    var drawableSize: CGSize = CGSizeZero
    var scale: Float = 1.0
    var transformModeValues: TransformModeValues? = nil
    
    var centerpointSnappedToHandle: simd_float2? = nil
    
    var metalWidthPerPixel: Float {
        scale / Float(max(drawableSize.width, drawableSize.height))
    }

    /*
     */
    var metalPixelSize: simd_float2  {
        let adjustment: simd_float2 = landscape ?  simd_float2(1, 1/imageAspectRatio) : simd_float2(1*imageAspectRatio, 1)
        return simd_float2(x: metalWidthPerPixel/adjustment.x, y: metalWidthPerPixel/adjustment.y)
    }
    
    var enableJoinCurves: Bool {
        // Only enable the join curves menu item if exactly 2 points are selected
        // and they are the beginning or end of different curves
        if selectedPoints.count != 2 {
            return false
        }
        let selectedPointsArray = Array(selectedPoints)
        let curv1Point = selectedPointsArray[0]
        let curve2Point = selectedPointsArray[1]
        if curv1Point.curveIndex == curve2Point.curveIndex {
            return false
        }
        let curve1 = curves[curv1Point.curveIndex]
        let curve2 = curves[curve2Point.curveIndex]
        if curve1.isClosedCurve || curve2.isClosedCurve {
            return false
        }
        return (curv1Point.pointIndex == 0 || curv1Point.pointIndex == curve1.points.count - 1) && (curve2Point.pointIndex == 0 || curve2Point.pointIndex == curve2.points.count - 1)
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
//        self.lineThickness = try container.decodeIfPresent(Float.self, forKey: .lineThickness) ?? 5
        self.brushSettings.lineHardness = try container.decodeIfPresent(Float.self, forKey: .lineHardness) ?? 2
        self.showControlPoints = try container.decode(Bool.self, forKey: .showControlPoints)

        self.viewportSize = DrawingInfo.defaultSize

    }
    
    // MARK: - Encode
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showSmoothingPoints, forKey: .showSmoothingPoints)
        try container.encode(smoothCurves, forKey: .smoothCurves)
        try container.encode(CodableColor(color: backgroundColor), forKey: .backgroundColor)
        try container.encode(brushSettings.lineHardness, forKey: .lineHardness)
        try container.encode(curves, forKey: .curves)
        try container.encode(showControlPoints, forKey: .showControlPoints)
    }
    
    init() {
        self.imageSize = DrawingInfo.defaultSize
        self.showSmoothingPoints = false
        self.backgroundColor = .white
        self.viewportSize = DrawingInfo.defaultSize
    }

    // MARK: - Editing Actions
    
    func flipHorizontally(vertex: SIMD2<Float>, around pivot: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(
            x: -vertex.x + 2 * pivot.x,
            y: vertex.y
        )
    }
    
    func flipVertically(vertex: SIMD2<Float>, around pivot: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(
            x: vertex.x,
            y: -vertex.y + 2 * pivot.y
        )
    }
    
    func flipVertex(_ vertex: SIMD2<Float>, vertically: Bool, around pivot: SIMD2<Float> ) -> SIMD2<Float> {
        return vertically ?
        SIMD2<Float>(
            x: vertex.x,
            y: -vertex.y + 2 * pivot.y
        )
        :
        SIMD2<Float>(
            x: -vertex.x + 2 * pivot.x,
            y: vertex.y
        )

    }

    func flipSelection(vertically: Bool) {
        
        struct SelectedCurvePoints: Hashable, Equatable {
            let curveIndex: Int
            var pointIndexes: Set<Int>
            func hash(into hasher: inout Hasher) {
                hasher.combine(curveIndex)
            }
            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.curveIndex == rhs.curveIndex
            }
        }
        
        guard var transformModeValues else { return }

        var selectedCurvePoints: Set<SelectedCurvePoints> = []
        
        // Loop through all the selected points
        for point in selectedPoints {
            let curveIndex = point.curveIndex
            let pointIndex = point.pointIndex
            if var selectedCurve = selectedCurvePoints.first(where: { $0.curveIndex == curveIndex }) {
                // If this curve is already in selectedCurvePoints, add the new point to its list of points.
                selectedCurve.pointIndexes.insert(pointIndex)
                selectedCurvePoints.update( with: selectedCurve)
            } else {
                // This is the first time we've seen this curve, so add it to selectedCurvePoints with this first point
                selectedCurvePoints.insert(SelectedCurvePoints(
                    curveIndex: point.curveIndex,
                    pointIndexes: [pointIndex]))
            }
        }
        // Loop through each curve that has selected points.
        for curvePoints in selectedCurvePoints {
            var curve = curves[curvePoints.curveIndex]
            
            // Loop through the selected points for a curve
            for selectedPointIndex in curvePoints.pointIndexes {
                // Flip that point Horizontally or vertically around the rotation point
                var point = curve.points[selectedPointIndex]
                point.coord = flipVertex(point.coord, vertically: vertically, around: transformModeValues.rotationPoint)
                curve.points[selectedPointIndex] = point
            }
            curves[curvePoints.curveIndex] = curve
        }
        // Now also flip all the drag handles
        for dragHandleIndex in 0 ..< transformModeValues.dragHandles.count  {
            let dragHandle = transformModeValues.dragHandles[dragHandleIndex]
            let coord = dragHandle.coord
            transformModeValues.dragHandles[dragHandleIndex].coord = flipVertex(coord, vertically: vertically, around: transformModeValues.rotationPoint)
            
            // Also udpate teh selection rectagle corners (use the values we already calculated.)
            switch dragHandle.handleType {
            case .topLeft:
                transformModeValues.topLeft = transformModeValues.dragHandles[dragHandleIndex].coord
            case .topRight:
                transformModeValues.topRight = transformModeValues.dragHandles[dragHandleIndex].coord
            case .bottomLeft:
                transformModeValues.bottomLeft = transformModeValues.dragHandles[dragHandleIndex].coord
            case .bottomRight:
                transformModeValues.bottomRight = transformModeValues.dragHandles[dragHandleIndex].coord
            default: break
            }
        }
        self.transformModeValues = transformModeValues
    }
    
    // The last curve is drawn on top, so put it at the end.
    func bringCurveToFront() {
        guard singleCurveSelected,
              let selectedPoint = selectedPoints.first else { return }
        let selectedCurveIndex = selectedPoint.curveIndex
        guard curves.count > 1, selectedCurveIndex != curves.count-1 else { return }
        let selectedCurve = curves.remove(at: selectedCurveIndex)
        curves.append(selectedCurve)
        let newSelectedPoints = selectedPoints.map { point in
            SelectedPoint(curveIndex: curves.count-1, pointIndex: point.pointIndex)
        }
        selectedPoints = Set(newSelectedPoints)
    }
    
    func moveCurveForward() {
        guard singleCurveSelected,
              let selectedPoint = selectedPoints.first else { return }
        let selectedCurveIndex = selectedPoint.curveIndex
        guard selectedCurveIndex != curves.count-1 else { return }
        let selectedCurve = curves[selectedCurveIndex]
        curves.insert(selectedCurve, at: selectedCurveIndex + 2)
        curves.remove(at: selectedCurveIndex)
        selectedPoints = Set(selectedPoints.map { point in
            SelectedPoint(curveIndex: selectedCurveIndex + 1, pointIndex: point.pointIndex
            )
        })
    }

    func moveCurveBackward() {
        guard singleCurveSelected,
              let selectedPoint = selectedPoints.first else { return }
        let selectedCurveIndex = selectedPoint.curveIndex
        guard selectedCurveIndex > 0 else { return }
        let selectedCurve = curves.remove(at: selectedCurveIndex)
        curves.insert(selectedCurve, at: selectedCurveIndex - 1)
        let newSelectedPoints = selectedPoints.map { point in
            SelectedPoint(curveIndex: selectedCurveIndex - 1, pointIndex: point.pointIndex)
        }
        selectedPoints = Set(newSelectedPoints)
  }
    
    func sendCurveToBack() {
        guard singleCurveSelected,
              let selectedPoint = selectedPoints.first else { return }
        let selectedCurveIndex = selectedPoint.curveIndex
        guard selectedCurveIndex > 0 else { return }
        let selectedCurve = curves.remove(at: selectedCurveIndex)
        curves.insert(selectedCurve, at: 0)
        let newSelectedPoints = selectedPoints.map { point in
            SelectedPoint(curveIndex: 0, pointIndex: point.pointIndex)
        }
        selectedPoints = Set(newSelectedPoints)
                                                                    
    }
    
    func joinCurves() {
        performGroupedEdit {
            let selectedPointsArray = Array(selectedPoints).sorted { $0.curveIndex < $1.curveIndex}
            let curve1Index = selectedPointsArray[0].curveIndex
            let curve1SelectedPoint = selectedPointsArray[0]
            let curve2Index = selectedPointsArray[1].curveIndex
            let curve2SelectedPoint = selectedPointsArray[1]
            let curve1BeginningIsSelected = curve1SelectedPoint.pointIndex == 0
            let curve2BeginningIsSelected = curve2SelectedPoint.pointIndex == 0
            var curve1 = curves[curve1Index]
            var curve2 = curves[curve2Index]
            switch (curve1BeginningIsSelected, curve2BeginningIsSelected) {
            case (true, true):
                /*
                 reverse points in curve2
                 append to points in curve1
                 delete curve 2
                 */
                curve2.points = curve2.points.reversed() + curve1.points
                curves[curve2Index] = curve2
                curves.remove(at: curve1Index)
            case (false, true):
                /*
                 append curve2 points into curve1
                 delete curve2.
                 */
                curve1.points += curve2.points
                curves[curve1Index] = curve1
                curves.remove(at: curve2Index)
            case (true, false):
                /*
                 append curve1 points into curve2
                 delete curve1.
                 */
                curve2.points += curve1.points
                curves[curve2Index] = curve2
                curves.remove(at: curve1Index)
            case (false, false):
                /*
                 reverse curve2 points
                 append points to curve1
                 delete curve2
                 */
                curve1.points += curve2.points.reversed()
                curves[curve1Index] = curve1
                curves.remove(at: curve2Index)
            }
            selectedPoints = []
        }
    }
        
    var uniqueSelectedCurveIndexes: [Int] {
         Array(Set(selectedPoints.map(\.curveIndex))).sorted{ $0 > $1 }
    }
    
    func deletePoints(deleteEntireCurve: Bool = false) {
        performGroupedEdit {
            if deleteEntireCurve {
                // TODO: Figure out what to do if more than one curve is selected.
                let curveIndexesToDelete = uniqueSelectedCurveIndexes
                for curveIndex in curveIndexesToDelete {
                    curves.remove(at: curveIndex)
                    selectedPoints = []
                    drawingMode = .idle

                }
            } else if  selectedPoints.count == 1 {
                let selectedPoint = selectedPoints.first!
                var pointIndex = selectedPoint.pointIndex
                
                var curve = curves[selectedPoint.curveIndex]
                curve.points.remove(at: selectedPoint.pointIndex)
                selectedPoints.remove(selectedPoint)

                if pointIndex > 0 {
                    pointIndex -= 1
                }
                if pointIndex >= 0 {
                    selectedPoints =  [SelectedPoint(curveIndex: selectedPoint.curveIndex, pointIndex: pointIndex)]
                }
                if curve.points.isEmpty {
                    curves.remove(at: selectedPoint.curveIndex)
                    selectedPoints = []
                } else {
                    curves[selectedPoint.curveIndex] = curve
                    if selectedPoint.pointIndex > curve.points.count - 1 {
                        selectedPoints =  [SelectedPoint(curveIndex: selectedPoint.curveIndex, pointIndex: curve.points.count - 1)]
                    }
                }
            } else {
                let selectedPointsArray = Array(selectedPoints).sorted {
                    ($0.curveIndex, $0.pointIndex) > ($1.curveIndex, $1.pointIndex)
                }
                
                for aPoint in selectedPointsArray {
                    var curve = curves[aPoint.curveIndex]
                    let pointIndex = aPoint.pointIndex
                    
                    curve.points.remove(at: pointIndex)
                    if curve.points.isEmpty {
                        curves.remove(at: aPoint.curveIndex)
                        selectedPoints = []
                    } else {
                        curves[aPoint.curveIndex] = curve
                    }
                    selectedPoints.remove(aPoint)
                }
            }
        }
    }

    // MARK: - Clipboard

    private static let pasteboardType = "com.wareto.drawingApp.copiedPoints"

    @discardableResult
    func copySelectedPoints() -> Bool {
        guard !selectedPoints.isEmpty else { return false }

        var curveGroups: [Int: [Int]] = [:]
        for sp in selectedPoints {
            curveGroups[sp.curveIndex, default: []].append(sp.pointIndex)
        }

        var copiedCurves: [CatmullRomCurve] = []
        for (curveIndex, pointIndices) in curveGroups.sorted(by: { $0.key < $1.key }) {
            let curve = curves[curveIndex]
            let points = pointIndices.sorted().map { curve.points[$0] }
            copiedCurves.append(CatmullRomCurve(
                color: curve.color,
                radius: curve.radius,
                outlineColor: curve.outlineColor,
                isClosedCurve: curve.isClosedCurve,
                points: points,
                hardness:  curve.hardness
            ))
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(copiedCurves) else { return false }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(Self.pasteboardType))
        #else
        UIPasteboard.general.setData(data, forPasteboardType: Self.pasteboardType)
        #endif

        return true
    }

    func cutSelectedPoints() {
        performGroupedEdit {
            guard copySelectedPoints() else { return }
            deletePoints()
        }
    }
    
    func selectAll() {
        //print("In \(#function)")
        guard curves.count > 0 else {
            selectedPoints = []
            return
        }
        var curveIndexes = [Int]()
        if !selectedPoints.isEmpty {
            for point in selectedPoints {
                curveIndexes.append(point.curveIndex)
            }
        } else {
            curveIndexes = [Int](0 ... curves.count-1)
        }
        for curveIndex in curveIndexes {
            let aCurve = curves[curveIndex]
            for pointIndex in 0 ..< aCurve.points.count {
                selectedPoints.insert(SelectedPoint(curveIndex: curveIndex, pointIndex: pointIndex))
                drawingMode = .editingCurve
            }
        }
    }
    
    func pastePoints() {
        #if os(macOS)
        guard let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(Self.pasteboardType)) else { return }
        #else
        guard let data = UIPasteboard.general.data(forPasteboardType: Self.pasteboardType) else { return }
        #endif

        guard let copiedCurves = try? JSONDecoder().decode([CatmullRomCurve].self, from: data) else { return }

        let offset: Float = 0.05
        selectedPoints = []
        for var curve in copiedCurves {
            for i in curve.points.indices {
                curve.points[i].coord.x += offset
                curve.points[i].coord.y -= offset
            }
            let newIndex = curves.count
            curves.append(curve)
            for pointIndex in curve.points.indices {
                selectedPoints.insert(SelectedPoint(curveIndex: newIndex, pointIndex: pointIndex))
            }
        }
        drawingMode = .editingCurve
    }

    var canPaste: Bool {
        #if os(macOS)
        return NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(Self.pasteboardType)) != nil
        #else
        return UIPasteboard.general.contains(pasteboardTypes: [Self.pasteboardType])
        #endif
    }

    // MARK: - Undo

    weak var undoManager: UndoManager?
    var suppressUndo = false

    func performGroupedEdit(_ edits: () -> Void) {
        registerUndo()
        suppressUndo = true
        edits()
        suppressUndo = false
    }

    func registerUndo() {
        guard let undoManager else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let snapshot = try? encoder.encode(self) else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.registerUndo()
            target.restore(from: snapshot)
        }
    }

    func restore(from data: Data) {
        guard let restored = try? JSONDecoder().decode(DrawingInfo.self, from: data) else { return }
        suppressUndo = true
        self.showSmoothingPoints = restored.showSmoothingPoints
        self.smoothCurves = restored.smoothCurves
        self.backgroundColor = restored.backgroundColor
//        self.lineThickness = restored.lineThickness
        self.brushSettings.lineHardness = restored.brushSettings.lineHardness
        self.curves = restored.curves
        self.showControlPoints = restored.showControlPoints
        self.drawingMode = .idle
        self.selectedPoints = []
        DispatchQueue.main.async { [weak self] in
            self?.suppressUndo = false
        }
    }
}
