//
//  NearbyDeviceDetailsView.swift
//
//
//  Created by Ben Gottlieb on 6/14/23.
//

import SwiftUI
import CrossPlatformKit
import Suite

public struct NearbyDeviceDetailsView: View {
	@ObservedObject var device: NearbyDevice
	@Environment(\.presentationMode) var dismiss
	
	public init(device: NearbyDevice) {
		self.device = device
	}
	
	public var body: some View {
		VStack(alignment: .leading) {
			ZStack {
				Text("Device Details").bold()
				Button("Done") { dismiss.wrappedValue.dismiss() }
					.frame(maxWidth: .infinity, alignment: .trailing)
					.padding()
			}
			ScrollView {
				VStack {
					Text("Device: \(String(describing: type(of: device)))")
					if let avatar = device.avatarImage {
						HStack {
							Image(uxImage: avatar)
								.resizable()
								.aspectRatio(contentMode: .fit)
								.frame(height: 120)
							
							VStack {
								Text("\(Int(avatar.size.width)) x \(Int(avatar.size.height))")
								Text("\(device.avatarName ?? "--")")
							}
						}
					} else {
						Text("Avatar: \(device.avatarName ?? "--")")
					}
					Text("Avatar Hash: \(device.discoveryInfo?[NearbyDevice.Keys.avatarHash] ?? "--")")
					Text("State: \(device.state.description)")
					Text("MCState: \(device.lastReceivedSessionState.description)")
					Text("PeerID: \(device.session?.myPeerID.description ?? "--")")
					Text("Last seen at: \(device.lastSeenAt.localTimeString(date: .none))")
					Text("Avatar name: \(device.avatarName ?? "--")")
					Text("Avatar requested at: \(device.avatarRequestedAt?.localTimeString(date: .none) ?? "--")")
					Text("Avatar received at: \(device.lastReceivedAvatarAt?.localTimeString(date: .none) ?? "--")")
					if let lastConnectedAt = device.lastConnectedAt {
						Text("Last connected at: \(lastConnectedAt.localTimeString(date: .none))")
					}
					Divider()
					
					if let info = device.discoveryInfo, !info.isEmpty {
						Text("Discovery Info").font(.caption)
						
						let keys = Array(info.keys)
						ForEach(keys.indices, id: \.self) { index in
							let key = keys[index]
							Text("\(key): \(info[key] ?? "--")")
						}
						Divider()
					}
					Text("Info requested at: \(device.infoRequestedAt?.localTimeString(date: .none) ?? "--")")
					if let info = device.deviceInfo, !info.isEmpty {
						Text("Device Info").font(.caption)
						
						let keys = Array(info.keys)
						ForEach(keys.indices, id: \.self) { index in
							let key = keys[index]
							Text("\(key): \(info[key] ?? "--")")
						}
						Divider()
					}
					
					Spacer()
				}
				.padding()
			}
			
			HStack {
				if #available(iOS 15.0, macOS 12, *) {
					if device.state.isConnected {
						Button("Disconnect", role: .destructive) { device.disconnectFromPeers() }
							.padding()
					} else {
						Button("Disconnect") { device.disconnectFromPeers() }
							.padding()
					}
				} else if device.state == .connecting {
					HStack {
						Text("Connecting…")
							.opacity(0.5)
						
						if #available(iOS 14.0, *) {
							ProgressView()
						}
					}
				} else {
					Button("Connect") { device.connect() }
						.padding()
				}
				
				Spacer()
				
				AsyncButton("Cycle") {
					device.disconnect()
					try? await Task.sleep(nanoseconds: 3_000_000_000)
					device.requestInfo()
					device.requestAvatar()
				}
				.padding()

				if device.state.isConnected {
					Button("Refresh Info") {
						device.requestInfo()
						device.requestAvatar()
					}
					.padding()
				}
			}
		}
	}
}
