//
//  SettingsView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 6/4/26.
//

import SwiftUI

enum UserDefaultsKeys: String {
    case useForceTouch
    case gridSpacing
}

var settingsChangedNotification = Notification.Name(rawValue: "settingsChanged")

struct SettingsView: View {
    
    
    var doneButtonuttonAction: () -> Void = { }
    
    @AppStorage(UserDefaultsKeys.useForceTouch.rawValue) var useForceTouch: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useForceTouch.rawValue)
    
    @AppStorage(UserDefaultsKeys.gridSpacing.rawValue) var gridSpacing: Double = 20
    //@AppStorage(UserDefaultsKeys.gridSpacing.rawValue) var gridSpacing: Double = UserDefaults.standard.double(forKey: UserDefaultsKeys.useForceTouch.rawValue)

    var body: some View {
        ZStack {
            VStack(alignment: .center) {
                #if os(iOS)
                    Text("Settings")
                        .padding(.top, 20)
                #endif
                Spacer()
                VStack(alignment: .leading, spacing: 30) {
                    HStack {
                        Toggle("Vary line thickness with touch force", isOn: $useForceTouch)
                            .frame(width: 300, alignment: .trailing)
                            .onChange(of: useForceTouch) {
                                let center = NotificationCenter.default
                                let userInfo = ["useForceTouch":  useForceTouch]
                                center.post(name: settingsChangedNotification, object: nil, userInfo: userInfo)
                            }
                    }
                    HStack(alignment: .center)   {
                        
                        Text("Grid Spacing")
                            .padding(.leading, 20)
                        Slider(value: $gridSpacing, in: 10...60, step: 5)
                            .frame(maxWidth: 200)
                            .onChange(of: gridSpacing) {
                                let center = NotificationCenter.default
                                let userInfo = ["gridSpacing":  gridSpacing]
                                center.post(name: settingsChangedNotification, object: nil, userInfo: userInfo)
                            }
                        Text("\(Int(gridSpacing))")
                            .padding(.trailing, 20)
                    }
                }
                Spacer()
                Spacer()
            }
#if os(iOS)
            VStack {
                Spacer()
                Button("Done") {
                    doneButtonuttonAction()
                }
                .padding(.bottom, 20)
            }
#endif

        }
    }
}

#Preview {
    SettingsView()
}
