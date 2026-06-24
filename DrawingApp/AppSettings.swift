//
//  AppSettings.swift
//  WareToCurves
//
//  Created by Duncan Champney on 6/23/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.

import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif


class AppSettings: ObservableObject {
    
    static var sharedSettings = AppSettings()
    
#if os(macOS)
    //                NSApp.keyWindow?.firstResponder?.tryToPerform(
    //                    Selector((trySelector)),
    //                    with: nil
    
#endif
    
    init() {
        dlog(context: .lifecycle, "in AppSettings.init()")
        DebugLog.flags.logIfAny.insert(DebugLog.performance)
        //DebugLog.flags.logIfAny.insert(DebugLog.newDev)
    }
    @Published var infoWindowString = ""
    @Published var showInfoInspector = false
    
#if os(macOS)
#endif

}
