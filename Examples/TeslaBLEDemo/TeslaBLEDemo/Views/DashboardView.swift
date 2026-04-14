//
//  DashboardView.swift
//  TeslaBLEDemo
//
//  Created by Jiaxin Shou on 2026/4/14.
//

import SwiftUI
import TeslaBLE

struct DashboardView: View {
    @Environment(VehicleController.self)
    private var controller

    @Environment(\.scenePhase)
    private var scenePhase

    @State
    private var isUnlocking = false

    @State
    private var isHonking = false

    @State
    private var showForgetConfirm = false

    var body: some View {
        List {
            Section("Status") {
                ConnectionStatusRow(state: controller.connectionState)

                LabeledContent {
                    Text(controller.pairedVIN ?? "—")
                        .font(.footnote)
                        .monospaced()
                } label: {
                    Label("VIN", systemImage: "car.fill")
                }

                LabeledContent {
                    Toggle(
                        "",
                        isOn: .init(
                            get: { controller.isLive },
                            set: { controller.setLive($0) },
                        ),
                    )
                    .labelsHidden()
                } label: {
                    Label("Live", systemImage: "play.fill")
                }
            }

            DriveStateSection(drive: controller.drive)

            Section("Commands") {
                Button {
                    Task {
                        isUnlocking = true
                        await controller.unlock()
                        isUnlocking = false
                    }
                } label: {
                    LabeledContent {
                        if isUnlocking {
                            ProgressView()
                        }
                    } label: {
                        Label("Unlock", systemImage: "lock.open.fill")
                    }
                }
                .disabled(controller.connectionState != .connected || isUnlocking)

                Button {
                    Task {
                        isHonking = true
                        await controller.honk()
                        isHonking = false
                    }
                } label: {
                    LabeledContent {
                        if isHonking {
                            ProgressView()
                        }
                    } label: {
                        Label("Honk", systemImage: "speaker.wave.2.fill")
                    }
                }
                .disabled(controller.connectionState != .connected || isHonking)
            }

            Section {
                Button("Forget this vehicle", role: .destructive) {
                    showForgetConfirm = true
                }
            } footer: {
                Text("Removes the stored key and VIN. You will need to pair again.")
            }
        }
        .refreshable { await controller.refreshDrive() }
        .navigationTitle("Dashboard")
        .alert(
            "Forget this vehicle?",
            isPresented: $showForgetConfirm,
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                Task {
                    await controller.disconnect()
                    controller.clearPairing()
                }
            }
        } message: {
            Text("This will remove the stored key and VIN from this device. You will need to pair again to control this vehicle.")
        }
        .task { await controller.connect() }
        .onDisappear { Task { await controller.disconnect() } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: Task { await controller.disconnect() }
            case .active: Task { await controller.connect() }
            default: break
            }
        }
    }
}

#if DEBUG

#Preview {
    DashboardView()
        .environment(VehicleController())
}

#endif
