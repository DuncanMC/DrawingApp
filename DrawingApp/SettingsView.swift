//
//  SettingsView.swift
//  DrawingApp
//
//  Created by Duncan Champney on 6/4/26.
//

import SwiftUI

enum UserDefaultsKeys: String {
    case useForceTouch
}

var settingsChangedNotification = Notification.Name(rawValue: "settingsChanged")

struct SettingsView: View {
    
    
    var doneButtonuttonAction: () -> Void = { }
    
    @AppStorage(UserDefaultsKeys.useForceTouch.rawValue) var useForceTouch: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.useForceTouch.rawValue)

    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            HStack {
                Spacer()
                Toggle("Vary line thickness with touch force", isOn: $useForceTouch)
                    .frame(width: 300, alignment: .trailing)
                    .onChange(of: useForceTouch) {
                        let center = NotificationCenter.default
                        let userInfo = ["useForceTouch":  useForceTouch]
                        center.post(name: settingsChangedNotification, object: nil, userInfo: userInfo)
                    }

                Spacer()
            }
            Spacer()
            Button("Done") {
                doneButtonuttonAction()
            }
            .padding(.bottom, 20)

        }
    }
}

#Preview {
    SettingsView()
}
