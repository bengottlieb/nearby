//
//  File.swift
//  iOSTestingHarness
//
//  Created by Ben Gottlieb on 6/13/23.
//  Copyright © 2023 Stand Alone, inc. All rights reserved.
//

import SwiftUI
import CrossPlatformKit

extension Date {
	var secondAndNanosecond: String {
		let components = Calendar.current.dateComponents([.second, .nanosecond], from: self)
		
		return String(format: "%02d.%03d", components.second ?? 0, (components.nanosecond ?? 0) / 10_000)
	}
}

@available(macOS 12.0, iOS 15.0, *)
public struct NearbyDevicesHUD: View {
	@ObservedObject var nearby = NearbySession.instance
	@State var selectedDevice: NearbyDevice?
	@ObservedObject var history = MessageHistory.instance
	@AppStorage("show_simulators_in_nearby_hud") var showSimulators = true
	@State var areSimulatorsPresent = false
	@Environment(\.dismiss) var dismiss
	var showDevices = true
	var showLog = true
	var showCloseButton = false

	public init(showDevices: Bool = true, showLog: Bool = true, showCloseButton: Bool = false) {
		self.showDevices = showDevices
		self.showLog = showLog
		self.showCloseButton = showCloseButton
	}
		
	public var body: some View {
		DeviceContainer(nearby.visibleDevices) { devices in
			if showDevices {
				let visibleDevices = showSimulators ? devices : devices.filter { $0.isSimulator }
				
				VStack(alignment: .leading) {
					ForEach(visibleDevices.sorted()) { device in
						Button(action: { selectedDevice = device }) {
							DeviceRow(device: device)
						}
						.buttonStyle(.plain)
					}
					if areSimulatorsPresent {
						Toggle("Show Simulators", isOn: $showSimulators.animation())
							.padding(.horizontal)
					}
				}

				if showLog {
					ScrollView {
						VStack {
							ForEach(history.history) { item in
								HistoryCell(item: item)
							}
						}
						.font(.body)
					}
					Button("Clear Log") { history.clearHistory() }
						.font(.body)
				}
			}
		}
		.frame(minWidth: 300, minHeight: 400)
		.padding()
		.overlay {
			if showCloseButton {
				Button("Close", systemImage: "xmark.circle") {
					dismiss()
				}
				.labelStyle(.iconOnly)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
				.padding()
				.imageScale(.large)
				.buttonStyle(.plain)
			}
		}
		.sheet(item: $selectedDevice) { device in NearbyDeviceDetailsView(device: device) }
	}

	struct HistoryCell: View {
		let item: MessageHistory.RecordedMessage
		
		var body: some View {
			HStack {
				HStack(spacing: 1) {
					Image(systemName: item.incoming ? "arrow.down" : "arrow.up")
					Text(item.date.secondAndNanosecond)
				}
				.font(.caption)
				
				Text(item.sender.name)
				Text(item.label)
				Spacer()
			}
			.opacity(item.incoming ? 1 : 0.5)
		}
	}
	
	struct DeviceRow: View {
		@ObservedObject var device: NearbyDevice
		
		var body: some View {
			HStack(spacing: 2) {
				Image(systemName: device.imageName)
					.foregroundColor(Color(device.stateColor))
					.padding(.horizontal, 4)
				
				Text(device.name)
				if let info = device.deviceInfo, !info.isEmpty {
					Text("{\(info.count)}")
				}
				if device.isSimulator { Text("[sim]") }
			}
			.padding(.vertical, 4)
		}
	}
}
