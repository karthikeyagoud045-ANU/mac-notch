//
//  BoringHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct BoringHeader: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @StateObject var tvm = ShelfStateViewModel.shared
    @ObservedObject var stats = SystemStatsManager.shared
    @ObservedObject var pomodoro = PomodoroManager.shared
	var body: some View {
        HStack(spacing: 0) {
            HStack {
                if (!tvm.isEmpty || coordinator.alwaysShowTabs) && Defaults[.boringShelf] {
                    TabSelectionView()
                } else if vm.notchState == .open {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            Button(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "web.camera")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                                
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Button(action: {
                            if pomodoro.phase == .idle {
                                pomodoro.startOrResume()
                            } else {
                                pomodoro.pause()
                            }
                        }) {
                            Capsule()
                                .fill(.black)
                                .frame(height: 30)
                                .overlay {
                                    HStack(spacing: 4) {
                                        Image(systemName: pomodoro.phase == .idle ? "timer" : (pomodoro.phase == .work ? "play.fill" : "cup.and.saucer.fill"))
                                            .foregroundColor(pomodoro.phase == .idle ? .white : .teal)
                                            .imageScale(.medium)
                                        if pomodoro.phase != .idle {
                                            Text(pomodoro.displayTime)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.horizontal, pomodoro.phase != .idle ? 8 : 0)
                                }
                                .frame(minWidth: 30)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            ScreenSnipManager.shared.startSnip()
                        }) {
                            Capsule()
                                .fill(.black)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "crop")
                                        .foregroundColor(.white)
                                        .imageScale(.medium)
                                }
                        }
                        .buttonStyle(PlainButtonStyle())

                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }

                        if vm.notchState == .open && coordinator.sneakPeek.show && coordinator.sneakPeek.type == .stats {
                            HStack(spacing: 6) {
                                Image(systemName: "cpu").font(.system(size: 10, weight: .semibold))
                                Text("\(stats.cpuUsage)%").font(.system(size: 10, weight: .semibold, design: .rounded))
                                Image(systemName: "memorychip").font(.system(size: 10, weight: .semibold))
                                Text("\(stats.memoryUsage)%").font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .animation(.smooth, value: stats.cpuUsage)
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
