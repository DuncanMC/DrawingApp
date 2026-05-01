//
//  DrawingAppApp.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//

import SwiftUI

@main
struct DrawingAppApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: DrawingAppDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
