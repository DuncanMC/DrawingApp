//
//  ContentView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 5/1/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: DrawingAppDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(DrawingAppDocument()))
}
