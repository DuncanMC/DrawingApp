//
//  File.swift
//  Wordzilla
//
//  Created by Duncan Champney on 2/15/24.
//  Copyright (c) 2024-2026 Duncan Champney. All rights reserved.

import Foundation
import SwiftUI

struct LoggingConditions {
    var logIfAny:   DebugLog
    var logIfAll:   DebugLog
    var dontLog:    DebugLog
    init(logIfAny: DebugLog = .none, logIfAll: DebugLog = .none, dontLog: DebugLog = .none) {
        self.logIfAny =  logIfAny
        self.logIfAll =  logIfAll
        self.dontLog =   dontLog
    }
}
struct DebugLog: OptionSet, CustomStringConvertible {
    static let timestamp =      DebugLog(rawValue: 1 << 0)  // $0001
    static let info =           DebugLog(rawValue: 1 << 1)  // $0002
    static let file =           DebugLog(rawValue: 1 << 2)  // $0004
    static let line =           DebugLog(rawValue: 1 << 3)  // $0008
    static let function =       DebugLog(rawValue: 1 << 4)  // $0010

    
    static let lifecycle =      DebugLog(rawValue: 1 << 5)  // $0020
    static let newDev =         DebugLog(rawValue: 1 << 6)  // $0040
    static let menuHandling =   DebugLog(rawValue: 1 << 7)  // $0080
    static let windowHandling = DebugLog(rawValue: 1 << 8)  // $0100
    static let displayMode    = DebugLog(rawValue: 1 << 9)  // $0200
    static let error          = DebugLog(rawValue: 1 << 10) // $0400
    static let performance =    DebugLog(rawValue: 1 << 11) // $0800
    static let infoLogging =    DebugLog(rawValue: 1 << 12) // $1000
    static let none =           DebugLog([])                // $0000
    
    let rawValue: Int
    // MARK: debugLog settings
    static var flags: LoggingConditions = LoggingConditions(logIfAny: [.none])
    
    var description: String {
        var result = [String]()
        if self.contains(.timestamp) { result.append(".timestamp") }
        if self.contains(.info) { result.append(".info") }
        if self.contains(.file) {result.append(".file")}
        if self.contains(.line) {result.append(".line")}
        if self.contains(.function) {result.append(".function")}
        if self.contains(.lifecycle) {result.append(".lifecycle")}
        if self.contains(.newDev) {result.append(".newDev")}
        if self.contains(.menuHandling) {result.append(".menuHandling")}
        if self.contains(.windowHandling) {result.append(".windowHandling")}
        if self.contains(.displayMode) {result.append(".displayMode")}
        if self.contains(.performance) {result.append(".performance")}
        if self.contains(.infoLogging) {result.append(".infoLogging")}
        if self.isEmpty {result.append(".none")}
        return "[" + result.joined(separator: ",") + "]"
    }
}



func dlog(function: String = #function,  file: String = #file, line: Int = #line, context: DebugLog = .info,_ stringToPrint: String) {
    guard DebugLog.flags.logIfAny.contains(context) || context.contains(.infoLogging)  else {
        return
    }
    var outputString = ""
    if DebugLog.flags.logIfAny.contains(.timestamp) || context.contains(.timestamp){
        outputString += "\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)): "
    }
    //timestamp
    if DebugLog.flags.logIfAny.contains(.file) || context.contains(.file) {
        outputString += "\(file): "
    }
    if DebugLog.flags.logIfAny.contains(.line) || context.contains(.line) {
        outputString += "[line \(line)] "
    }
    if DebugLog.flags.logIfAny.contains(.function) || context.contains(.function)  {
        outputString += "\(function): "
    }
    outputString += "\(stringToPrint)"
    if context.contains(.infoLogging) || context.contains(.error){
        AppSettings.sharedSettings.infoWindowString += "\(outputString )\n"
    }
    // If there are other output flags that are set, print the output to the console
    if !DebugLog.flags.logIfAny.intersection(context).isEmpty {
        print(outputString)
    }
}
