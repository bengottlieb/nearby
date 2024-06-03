//
//  DeviceLocator.swift
//
//  Created by Ben Gottlieb on 5/18/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import MultipeerConnectivity

protocol DeviceLocatorDelegate: AnyObject {
	func didLocate(device: NearbyDevice)
	func didFailToLocateDevice()
}

class NearbyScanner: NSObject {
	var advertiser: MCNearbyServiceAdvertiser!
	var browser: MCNearbyServiceBrowser!
	weak var delegate: DeviceLocatorDelegate!
	
	var isLocating = false
	var isBrowsing = false { didSet { self.updateState() }}
	var isAdvertising = false { didSet { self.updateState() }}
	
	var peerID: MCPeerID { return NearbySession.instance.peerID }
	
	init(delegate: DeviceLocatorDelegate) {
		super.init()
		
		self.delegate = delegate
		self.advertiser = MCNearbyServiceAdvertiser(peer: self.peerID, discoveryInfo: NearbyDevice.localDevice.discoveryInfo, serviceType: NearbySession.instance.serviceType)
		self.advertiser.delegate = self
		
		self.browser = MCNearbyServiceBrowser(peer: self.peerID, serviceType: NearbySession.instance.serviceType)
		self.browser.delegate = self
	}
}

extension NearbyScanner {
	func stopLocating() {
		self.browser?.stopBrowsingForPeers()
		self.advertiser?.stopAdvertisingPeer()
		self.isLocating = false
		self.isBrowsing = false
		self.isAdvertising = false
	}
	
	func startLocating() {
		self.isLocating = true
		self.isBrowsing = true
		self.isAdvertising = true
		
		self.browser.startBrowsingForPeers()
		self.advertiser.startAdvertisingPeer()
	}
	
	func updateState() {
		if self.isLocating, !self.isAdvertising, !self.isBrowsing {
			self.isLocating = false
		}
	}
	
	func reinvite(device: NearbyDevice) {
		if device.state.canConnect {
			device.invite(with: self.browser)
		}
	}
}

extension NearbyScanner: MCNearbyServiceAdvertiserDelegate {
	func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
		//print("Received invitation from \(peerID)")
		Task {
			if let device = await NearbySession.instance.device(for: peerID) {
				device.receivedInvitation(from: peerID, withContext: context, handler: invitationHandler)
			} else if let data = context, let info = try? JSONDecoder().decode([String: String].self, from: data) {
				let device = await NearbySession.deviceClass.init(peerID: peerID, info: info)
				self.delegate.didLocate(device: device)
			} else {
				invitationHandler(false, nil)
			}
		}
	}
	
	public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
		logToConsole("Error when starting advertising: \(error)")
		self.isAdvertising = false
	}
}

extension NearbyScanner: MCNearbyServiceBrowserDelegate {
	func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
		guard let info else {
			logToConsole("No discovery info found for \(peerID.displayName)")
			return
		}
		logToConsole("Found peer: \(peerID.displayName)", onlyWhenDebugging: true)
		Task {
			var device = await NearbySession.instance.device(for: peerID)
			if device == nil { device = await NearbySession.deviceClass.init(peerID: peerID, info: info) }
			guard let device else { return }
			device.lastSeenAt = Date()
			self.delegate.didLocate(device: device)
			if device.state != .connected && device.state != .invited && device.state != .connecting {
				if device.state != .none {
					device.stopSession()
				}
				
				device.state = .found
			}
			device.invite(with: self.browser)
		}
	}
	
	func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		logToConsole("Lost peer: \(peerID.displayName)", onlyWhenDebugging: true)
		Task {
			if let device = await NearbySession.instance.device(for: peerID) {
				device.disconnect()
			}
		}
	}
	
	func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
		logToConsole("Error when starting browsing: \(error)")
		self.isBrowsing = false
	}
}
