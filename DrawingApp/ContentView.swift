//
//  ContentView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//  Copyright (c) 2026 Duncan Champney. All rights reserved.
//

import SwiftUI

@MainActor struct ContentView: View {
    @ObservedObject var drawingInfo: DrawingInfo
    
    var viewModel: ViewModel
    
    var toggleAlignment: Alignment {
    #if os(macOS)
            return .leading
    #else
            return .trailing
    #endif

    }

    var body: some View {
        VStack {
            VStack {
                DrawingView(drawingInfo: drawingInfo)
                    .frame(width: DrawingInfo.defaultSize.width, height: DrawingInfo.defaultSize.height)
                    .border(Color.blue, width: 4)
                    .aspectRatio(drawingInfo.imageSize, contentMode: .fit)
                TextEditor(text: $drawingInfo.text)
                    .frame(maxHeight: 50)
                HStack {
                    Button("Test") {
                        drawingInfo.text += " Extra words."
                    }

                    Toggle(isOn: $drawingInfo.toggleIsOn) {
                        Text("Toggle is on")
                    }
                    .frame(maxWidth: 200, alignment: toggleAlignment)

                    Slider(value: $drawingInfo.linePlacement, in: -1...1) {
                        
                    }
                    .frame(maxWidth: 200)
                }
            }
        }
    }
    
    init(drawingInfo: DrawingInfo) {
        self.drawingInfo = drawingInfo
        self.viewModel = .init(drawingInfo: drawingInfo)
    }
}

#Preview {
    ContentView(drawingInfo: DrawingInfo(title: "foo", text: "bar"))
}
