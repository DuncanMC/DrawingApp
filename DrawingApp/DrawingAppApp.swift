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
    
    @ObservedObject var appSettings: AppSettings = AppSettings.sharedSettings


    var body: some Scene {
        DocumentGroup(newDocument: { DrawingAppDocument() }) { config in
            ContentView(drawingInfo: config.document.drawingInfo)
        }
        .commands {
            DrawingCommands()
        }
        #if os(macOS)
            Settings {
                SettingsView()
            }
            Window("Info", id: "Info_window") {
                TextEditor(text: $appSettings.infoWindowString)
                        .font(Font.custom("Courier", size: 12))
            }
        #endif

    }
}
