//
//  DrawingAppApp.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI

@main
@MainActor
struct DrawingAppApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: DrawingAppDocument()) { @MainActor file in
            ContentView(drawingInfo: file.$document.drawingInfo)
        }
    }
}

