//
//  ContentView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//

import SwiftUI

@MainActor struct ContentView: View {
    @Binding var drawingInfo: DrawingInfo

    var body: some View {
        VStack {
            VStack {
                DrawingView(drawingInfo: $drawingInfo)
                    .frame(width: DrawingInfo.defaultSize.width, height: DrawingInfo.defaultSize.height)
                    .border(Color.blue, width: 4)
                    .aspectRatio(drawingInfo.imageSize, contentMode: .fit)
                TextEditor(text: $drawingInfo.text)
                    .frame(maxHeight: 50)
                HStack {
                    Button("Stuff") {
                        drawingInfo.text += " Extra words."
                    }

                    Toggle(isOn: $drawingInfo.toggleIsOn) {
                        Text("Toggle is on")
                    }
                    Slider(value: $drawingInfo.linePlacement, in: -1...1) {
                        
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView(drawingInfo: .constant(DrawingInfo(title: "foo", text: "bar")))
}
