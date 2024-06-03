//
//  NearbyDevice+Comms.swift
//  Internal
//
//  Created by Ben Gottlieb on 6/13/23.
//

import Foundation
import MultipeerConnectivity
import CrossPlatformKit
import Studio

extension NearbyDevice {
	func session(didStartReceivingResourceWithName resourceName: String, with progress: Progress) {
		
	}
	
	func session(didFinishReceivingResourceWithName resourceName: String, at localURL: URL?, withError error: Error?) {
	}
	
	func disconnectFromPeers() async {
		await withCheckedContinuation { continuation in
			closeStream()
			disconnectFromPeers { continuation.resume() }
		}
	}
	
	func disconnectFromPeers(completion: (() -> Void)? = nil) {
		logToConsole("Disconnecting from peers", onlyWhenDebugging: true)
		#if os(iOS)
			guard let application = NearbySession.instance.application else { return }
			let taskID = application.beginBackgroundTask {
				completion?()
			}
			self.send(message: NearbySystemMessage.disconnect, completion: {
				self.stopSession()
				DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
					completion?()
					application.endBackgroundTask(taskID)
				}
			})
		#else
			self.send(message: NearbySystemMessage.disconnect, completion: { completion?() })
		#endif
	}

	@discardableResult
	func invite(with browser: MCNearbyServiceBrowser) -> Bool {
		guard let info = NearbyDevice.localDevice.discoveryInfo, let data = try? JSONEncoder().encode(info) else { return false }
		self.startSession()
		guard let session = self.session else { return false }
		self.state = .invited
		browser.invitePeer(self.peerID, to: session, withContext: data, timeout: self.invitationTimeout)
		return true
	}
		
	func receivedInvitation(from: MCPeerID, withContext context: Data?, handler: @escaping (Bool, MCSession?) -> Void) {
		if !state.isConnected, state != .provisioned {
			state = deviceInfo == nil ? .connected : .provisioned
		}
		startSession()
		lastSeenAt = Date()
		handler(true, session)
	}
	
	func session(didChange state: MCSessionState) {
		self.lastReceivedSessionState = state
		var newState = self.state
		let oldState = self.state
		
		switch state {
		case .connected:
			lastSeenAt = Date()
			newState = deviceInfo == nil ? .connected : .provisioned
		case .connecting:
			lastSeenAt = Date()
			newState = .connecting
			self.startSession()
		case .notConnected:
			newState = .found
			// no longer disconnect if we get a session(:peer:didChangeState:) message
//			self.disconnect()
//			Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in NearbySession.instance.deviceLocator?.reinvite(device: self) }

		@unknown default: break
		}
		
		if newState == self.state {
			return
		}
		self.state = newState
		defer { Notifications.deviceChangedState.post(with: self) }
		
		if self.state.isConnected {
			if NearbySession.instance.alwaysRequestInfo, self.state == .connected { sendDeviceInfo() }
			return
		} else if self.state == .connecting {
			self.startSession()
		}
		
		if !self.state.isConnected, oldState.isConnected {
			Notifications.deviceDisconnected.post(with: self)
		}
		objectWillChange.sendOnMain()
	}
	
	public func send(dictionary: [String: String], completion: (() -> Void)? = nil) {
		if isLocalDevice || session == nil {
			completion?()
			return
		}

		logToConsole("Sending dictionary \(dictionary) to \(name)")
		let payload = NearbyMessagePayload(message: NearbySystemMessage.DictionaryMessage(dictionary: dictionary))
		send(payload: payload)
		completion?()
	}
	
	public func send<MessageType: NearbyMessage>(message: MessageType, completion: (() -> Void)? = nil) {
		if isLocalDevice {
			logToConsole("Not sending \(message) to local device.")
			completion?()
			return
		}
		
		if session == nil {
			logToConsole("Not sending \(message), no session.")
			completion?()
			return
		}

		logToConsole("Sending \(message.command) as a \(type(of: message)) to \(name)", onlyWhenDebugging: true)
		let payload = NearbyMessagePayload(message: message)
		send(payload: payload)
		completion?()
	}
	
	func send(payload: NearbyMessagePayload?) {
		guard let payload else { return }
		
		MessageHistory.instance.record(payload: payload, to: self)
		do {
			try session?.send(payload.payloadData, toPeers: [peerID], with: .reliable)
		} catch {
			logToConsole("Error \(error) when sending to \(name)")
		}
	}
	 
	public func send(file url: URL, named name: String, completion: ((Error?) -> Void)? = nil) {
		  session?.sendResource(at: url, withName: name, toPeer: peerID, withCompletionHandler:  completion)
	 }
	
	func session(didReceive data: Data) {
		guard let payload = NearbyMessagePayload(data: data) else {
			logToConsole("Failed to decode message from \(data)")
			return
		}
		
		MessageHistory.instance.record(payload: payload, from: self)

		if let message = InternalRouter.instance.route(payload, from: self) {
			delegate?.didReceive(message: message, from: self)
		} else if let message = NearbySession.instance.messageRouter?.route(payload, from: self) {
			delegate?.didReceive(message: message, from: self)
		}
	}
	
	public func connect() {
		if state != .connecting {
			NearbySession.instance.deviceLocator?.reinvite(device: self)
		}
	}
	
	public func disconnect() {
		closeStream()
		self.state = .disconnected
		Notifications.deviceDisconnected.post(with: self)
		self.stopSession()
	}
	
	func stopSession() {
		logToConsole("Stopping: \(self.session == nil ? "nothing" : "session")")
		self.session?.disconnect()
		self.session = nil
		self.state = .disconnected
	}
	
	func startSession() {
		if self.session == nil {
			self.session = MCSession(peer: NearbyDevice.localDevice.peerID, securityIdentity: nil, encryptionPreference: NearbySession.instance.useEncryption ? .required : .none)
			self.session?.delegate = self
		}
	}
}
