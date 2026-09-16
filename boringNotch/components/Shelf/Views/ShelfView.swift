//
//  ShelfView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        CalendarView(compact: false)
            .environmentObject(vm)
            .padding(.top, 4)
            .onAppear {
                Task {
                    await CalendarManager.shared.checkCalendarAuthorization()
                    await CalendarManager.shared.updateCurrentDate(Date.now)
                }
            }
    }
}
