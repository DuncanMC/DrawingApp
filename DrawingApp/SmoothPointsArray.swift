//
//  SmoothPointsArray.swift
//  Catmull-Rom smoothing
//
//  Created by Duncan Champney on 12/30/16.
//  Copyright © 2016 Duncan Champney. All rights reserved.
//

import simd
import Foundation


var metalWidthPerPixel: Float = 1000/2

public typealias  pointsArraysTuple = (
  points: [simd_float2],
  tempSmoothedPoints: [simd_float2],
  smoothedPoints: [simd_float2]
)

/**
 This function adjust the "granularity" value (The number of smoothing points to be added) up for control points that are far away and down for control points that are very close together.
 
 - parameter granularity: The starting granularity value
 - parameter startPoint: The starting control point where the smoothing points will be added
 - parameter endPoint: The ending control point where smoothing points will be added.
 
 - Returns: the adjusted granularity value
 */
internal func adjustedGranularity(_ granularity: Int,
                                  startPoint: simd_float2,
                                  endPoint: simd_float2) -> Int {
  var xDistance = abs(startPoint.x - endPoint.x) / metalWidthPerPixel
  xDistance *= xDistance
  var yDistance = abs(startPoint.y - endPoint.y) / metalWidthPerPixel
  yDistance *= yDistance
  let distance = xDistance+yDistance
  var thisGranularity = granularity
  if distance > 10000 {
    thisGranularity *=  4
  }
  else if distance > 4000 {
    thisGranularity *=  2
  }
  else if distance < 20 {
    thisGranularity = 0
  }
  else if distance < 500  && thisGranularity > 3 {
    thisGranularity /=  2
  }

  return thisGranularity
}

/**
 This function takes an array of 4 control points and returns an array of smoothed points that should be inserted between the second and 3rd point in the source array.
 
 - parameter source: The array of 4 source control points
 - parameter granularity: The number of intermediate points to add between the 2nd and 3rd point. The number of smoothing points will be increased when the middle control points are far away, and decreased when the control points are close together.
 - returns: an array of smoothed points, including the middle 2 source control points
 */

public func smoothedPointsFromArrayOf4Points(_ source: [simd_float2],
                                             granularity: Int,
                                             adjustGranularity: Bool = true) -> [simd_float2] {
  
  var result: [simd_float2] = []
  
  result += [source[1]]
  
  let p0 = source[0]
  let p1 = source[1]
  let p2 = source[2]
  let p3 = source[3]
  let thisGranularity: Int
  if adjustGranularity {
    thisGranularity = adjustedGranularity(granularity , startPoint: p1, endPoint: p2)
  }
  else {
    thisGranularity = granularity
  }
  if thisGranularity > 0 {
    for i in 1 ... thisGranularity {
      let t: Float = Float(i) * 1.0 / Float(thisGranularity+1)
      let tt = t * t
      let ttt = tt * t
      
      var pi = simd_float2.zero;
      var part1 = 2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x
      var part2 = (3.0 * p1.x - p0.x - 3.0 * p2.x + p3.x)
        pi.x = 0.5 * (2.0 * p1.x + (p2.x - p0.x) * t + part1 * tt + part2 * ttt)
      
      part1 = 2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y
      part2 = (3.0 * p1.y - p0.y - 3.0 * p2.y + p3.y)
      pi.y = 0.5 * (2.0 * p1.y + (p2.y - p0.y) * t +
        part1 * tt +
        part2 * ttt)
      result.append(pi)
    }
  }
  result.append(p2)

  return result
}

/**
 This function takes a new point and a starting array of control points and returns a tuple containing the updated array of all control points, plus an array of smoothed points that won't change, and an array of smoothed points that will change when the next control point is added to the curve.
 - Parameter point: the new point to add
 - Parameter granularity: The base number of smoothing points to add (defalt value = 4). The function will add more than this number of points when the distance betwee control points is large, and less when the distance between control points is small.
 - Parameter inputPoints: The control points that have already been added.
 - Returns: A pointsArraysTuple containging the updated array of control points, an array of "temporary" smoothed points that may change, and an array, smoothedPoints, which won't change when another control point is added.
 */
public func newSmoothedPoints(_ point: simd_float2,
                              granularity:  Int = 4,
                              inputPoints: [simd_float2]?) -> pointsArraysTuple {
  var finalPoints = inputPoints ?? [simd_float2]()
  finalPoints.append(point)
  
  var tempSmoothedPoints =  [simd_float2]()
  var newSmoothedPoints = [simd_float2]()
  var result: pointsArraysTuple
  
  var source: [simd_float2] = []
  
  switch finalPoints.count {
  case 1, 2:
    //1 or 2 points is not enough for a curve, so just return the input points
    result = (finalPoints, finalPoints, [])
    
  //When we have a total of 3 control points, we duplicate the starting point.
  //For > 3 control points,
  //we simply use the last 3 points from the inputPoints array plus the new point.
  case 3 ..< Int.max:
    let firstPointIndex = (finalPoints.count == 3) ? 0 : finalPoints.count-4
    source = [finalPoints[firstPointIndex],
              finalPoints[finalPoints.count-3],
              finalPoints[finalPoints.count-2],
              point]
    
    newSmoothedPoints = smoothedPointsFromArrayOf4Points(source, granularity: granularity)
    source = [finalPoints[finalPoints.count-3], finalPoints[finalPoints.count-2], point, point]
    tempSmoothedPoints = smoothedPointsFromArrayOf4Points(source, granularity: granularity)
    result = (finalPoints, tempSmoothedPoints, newSmoothedPoints)
  default:
    result = (finalPoints, [], [])
  }
  return result
  }
  
/**
 This function takes an array of control points and returns a new array of points where intermediate points have been added to create a smooth curve beween the control points.
 - Parameter array: The array of control points
 - Parameter granularity: The base number of smoothing points to add (defalt value = 4). The function will add more than this number of points when the distance betwee control points is large, and less when the distance between control points is small.
 - Returns: The array of points that define the smoothed curve. The points from the input array will be included in the array of smoothed points.

 */
public func smoothPointsInArray(_ array: [simd_float2],
                                granularity: Int = 4,
                                adjustGranularity: Bool = true,
                                makeClosedLoop: Bool = false) -> ([simd_float2], String) {
  
  let startTime = Date().timeIntervalSinceReferenceDate
  guard array.count > 2 else {
    return (array, "")
  }
  
  var source = array
  var result: [simd_float2] = []
  
  guard let first = array.first else {
    return (array, "")
  }
    if !makeClosedLoop {
        source.insert(first, at: 0)
        source.insert(first, at: 0)
    }
  
  guard let last = array.last else {
    return (array, "")
  }
    if !makeClosedLoop {
        source.append(last)
    }
  
  result.append(first)
    
    let start = makeClosedLoop ? 2 : 4
    let end = makeClosedLoop ? source.count+2 : source.count
  
    for index in start ..< end  {
    let p0 = source[(index + source.count - 3) % source.count]
    let p1 = source[(index + source.count - 2) % source.count]
    let p2 = source[(index + source.count - 1) % source.count]
    let p3 = source[(index + source.count) % source.count]
    let thisGranularity: Int
    if adjustGranularity {
      thisGranularity = adjustedGranularity(granularity , startPoint: p1, endPoint: p2)
    }
    else {
      thisGranularity = granularity
    }
     if thisGranularity == 0 {
      result.append(p2)
      continue
    }
    for i in 1 ... thisGranularity {
      let t: Float = Float(i) * 1.0 / Float(thisGranularity+1)
      let tt = t * t
      let ttt = tt * t
      
      var pi = simd_float2.zero;
      var part1 = 2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x
      var part2 = (3.0 * p1.x - p0.x - 3.0 * p2.x + p3.x)
      pi.x = 0.5 * (2.0 * p1.x + (p2.x - p0.x) * t +
        part1 * tt +
        part2 * ttt)
      
      part1 = 2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y
      part2 = (3.0 * p1.y - p0.y - 3.0 * p2.y + p3.y)
      pi.y = 0.5 * (2.0 * p1.y + (p2.y - p0.y) * t +
        part1 * tt +
        part2 * ttt)
      result.append(pi)
    }
    result.append(p2)
  }
    if !makeClosedLoop {
        result.append(last)
    }
  let elapsed = Date().timeIntervalSinceReferenceDate - startTime
  let timeString = String(format: "%lu points, added %lu, in %.5f sec",
                          array.count,
                          result.count - array.count,
                          elapsed)
  return (result, timeString)
}
