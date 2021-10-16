//
//  NearbyDevice.swift
//
//  Created by Ben Gottlieb on 5/18/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import CrossPlatformKit
import Studio

#if canImport(Combine)
import SwiftUI

@available(OSX 10.15, iOS 13.0, *)
extension NearbyDevice: ObservableObject, Identifiable {
	public var id: String { self.peerID.id }
}

extension MCPeerID: Identifiable {
	public var id: String {
		let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
		return data?.base64EncodedString() ?? "MCPeerID"
	}
}
#endif

public protocol NearbyDeviceDelegate: AnyObject {
	func didReceive(message: NearbyMessage, from: NearbyDevice)
	func didReceiveFirstInfo(from: NearbyDevice)
	func didChangeInfo(from: NearbyDevice)
	func didChangeState(for: NearbyDevice)
}

open class NearbyDevice: NSObject {
	public struct Notifications {
		public static let deviceChangedState = Notification.Name("device-state-changed")
		public static let deviceConnected = Notification.Name("device-connected")
		public static let deviceConnectedWithInfo = Notification.Name("device-connected-with-info")
		public static let deviceDisconnected = Notification.Name("device-disconnected")
		public static let deviceChangedInfo = Notification.Name("device-changed-info")
	}
	
	public static let localDevice = NearbySession.deviceClass.init(asLocalDevice: true)
	
	public enum State: Int, Comparable, CustomStringConvertible { case none, found, invited, connecting, connected
		public var description: String {
			switch self {
			case .none: return "None"
			case .found: return "Found"
			case .invited: return "Invited"
			case .connected: return "Connected"
			case .connecting: return "Connecting"
			}
		}
		
		public var color: UXColor {
			switch self {
			case .none: return .gray
			case .found: return .yellow
			case .invited: return .orange
			case .connected: return .green
			case .connecting: return .blue
			}
		}
		
		public var contrastingColor: UXColor {
			switch self {
			case .found, .invited, .connected: return .black
			default: return .white
			}
		}
		
		public static func < (lhs: State, rhs: State) -> Bool { return lhs.rawValue < rhs.rawValue }

	}
	
	public var lastReceivedSessionState = MCSessionState.connected
	open var discoveryInfo: [String: String]?
	public var deviceInfo: [String: String]? { didSet {
		if self.isLocalDevice {
			NearbySession.instance.localDeviceInfo = deviceInfo ?? [:]
			return
		}
		if oldValue == nil {
			self.delegate?.didReceiveFirstInfo(from: self)
			NearbyDevice.Notifications.deviceConnectedWithInfo.post(with: self)
			NearbyDevice.Notifications.deviceChangedInfo.post(with: self)
		} else if self.deviceInfo != oldValue {
			self.delegate?.didChangeInfo(from: self)
			NearbyDevice.Notifications.deviceChangedInfo.post(with: self)
		}
	}}
	public var displayName: String { didSet { sendChanges() }}
	public weak var delegate: NearbyDeviceDelegate?
	public let peerID: MCPeerID
	public let isLocalDevice: Bool
	public var uniqueID: String
	
	open var state: State = .none { didSet {
		defer { self.sendChanges() }
		if self.state == .connected {
			if self.deviceInfo != nil { NearbyDevice.Notifications.deviceConnectedWithInfo.post(with: self) }
			NearbyDevice.Notifications.deviceConnected.post(with: self)
		}
		if self.state == oldValue { return }
		//Logger.instance.log("\(self.displayName), \(oldValue.description) -> \(self.state.description)")
		self.delegate?.didChangeState(for: self)
		self.checkForRSVP(self.state == .invited)
	}}
	
	var idiom: String = "unknown"
	var isIPad: Bool { return idiom == "pad" }
	var isIPhone: Bool { return idiom == "phone" }
	var isMac: Bool { return idiom == "mac" }

	public var session: MCSession?
	public let invitationTimeout: TimeInterval = 30.0
	weak var rsvpCheckTimer: Timer?
	
	public var attributedDescription: NSAttributedString {
		if self.isLocalDevice { return NSAttributedString(string: "Local Device", attributes: [.foregroundColor: UXColor.black]) }
		return NSAttributedString(string: self.displayName, attributes: [.foregroundColor: self.state.color, .font: UXFont.boldSystemFont(ofSize: 14)])
	}
	
	open override var description: String {
		var string = self.displayName
		if self.isIPad { string += ", iPad" }
		if self.isIPhone { string += ", iPhone" }
		if self.isMac { string += ", Mac" }
		return string
	}

	public required init(asLocalDevice: Bool) {
		self.isLocalDevice = asLocalDevice
		self.uniqueID = MCPeerID.deviceSerialNumber
		self.discoveryInfo = [
			Keys.name: MCPeerID.deviceName,
			Keys.unique: self.uniqueID
		]
		
		if asLocalDevice {
			#if os(macOS)
				self.idiom = "mac"
				self.discoveryInfo?[Keys.idiom] = "mac"
			#endif
			#if os(iOS)
				switch UIDevice.current.userInterfaceIdiom {
				case .phone: idiom = "phone"
				case .pad: idiom = "pad"
				case .mac: idiom = "mac"
				default: idiom = "unknown"
				}
				self.discoveryInfo?[Keys.idiom] = idiom
			#endif
		}
		
		self.peerID = MCPeerID.localPeerID
		self.displayName = MCPeerID.deviceName
		super.init()
	}
	
	public required init(peerID: MCPeerID, info: [String: String]) {
		self.isLocalDevice = false
		self.peerID = peerID
		self.displayName = NearbySession.instance.uniqueDisplayName(from: self.peerID.displayName)
		self.discoveryInfo = info
		self.uniqueID = info[Keys.unique] ?? peerID.displayName
		if let idiom = info[Keys.idiom] {
			self.idiom = idiom
		}
		super.init()
		#if os(iOS)
			NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
		#endif
		self.startSession()
	}
	
	@objc func enteredBackground() {
		self.disconnectFromPeers(completion: nil)
	}
	
	func disconnectFromPeers(completion: (() -> Void)?) {
		Logger.instance.log("Disconnecting from peers")
		#if os(iOS)
			let taskID = NearbySession.instance.application.beginBackgroundTask {
				completion?()
			}
			self.send(message: NearbySystemMessage.disconnect, completion: {
				self.stopSession()
				DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
					completion?()
					NearbySession.instance.application.endBackgroundTask(taskID)
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
		self.state = .connected
		self.startSession()
		handler(true, self.session)
	}
	
	func session(didChange state: MCSessionState) {
		self.lastReceivedSessionState = state
		var newState = self.state
		let oldState = self.state
		
		switch state {
		case .connected:
			newState = .connected
		case .connecting:
			newState = .connecting
			self.startSession()
		case .notConnected:
			newState = .found
			self.disconnect()
			Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in NearbySession.instance.deviceLocator?.reinvite(device: self) }

		@unknown default: break
		}
		
		if newState == self.state {
			return
		}
		self.state = newState
		defer { Notifications.deviceChangedState.post(with: self) }
		
		if self.state == .connected {
			NearbyDevice.Notifications.deviceConnected.post(with: self)
			if self.deviceInfo != nil { NearbyDevice.Notifications.deviceConnectedWithInfo.post(with: self) }
			if NearbySession.instance.alwaysRequestInfo {
				self.send(message: NearbySystemMessage.DeviceInfo())
			}
			return
		} else if self.state == .connecting {
			self.startSession()
		}
		
		if self.state != .connected, oldState == .connected {
			Notifications.deviceDisconnected.post(with: self)
		}
	}
	
	open func disconnect() {
		self.state = .none
		Notifications.deviceDisconnected.post(with: self)
		self.stopSession()
	}
	
	func stopSession() {
		Logger.instance.log("Stopping: \(self.session == nil ? "nothing" : "session")")
		self.session?.disconnect()
		self.session = nil
	}
	
	func startSession() {
		if self.session == nil {
			self.session = MCSession(peer: NearbyDevice.localDevice.peerID, securityIdentity: nil, encryptionPreference: NearbySession.instance.useEncryption ? .required : .none)
			self.session?.delegate = self
		}
	}
	
	open func send(dictionary: [String: String], completion: (() -> Void)? = nil) {
		if self.isLocalDevice || self.session == nil {
			completion?()
			return
		}

		Logger.instance.log("Sending dictionary \(dictionary) to \(self.displayName)")
		let payload = NearbyMessagePayload(message: NearbySystemMessage.DictionaryMessage(dictionary: dictionary))
		self.send(payload: payload)
		completion?()
	}
	
	open func send<MessageType: NearbyMessage>(message: MessageType, completion: (() -> Void)? = nil) {
		if self.isLocalDevice || self.session == nil {
			completion?()
			return
		}

		Logger.instance.log("Sending \(message.command) as a \(type(of: message)) to \(self.displayName)")
		let payload = NearbyMessagePayload(message: message)
		self.send(payload: payload)
		completion?()
	}
	
	func send(payload: NearbyMessagePayload?) {
		guard let data = payload?.payloadData else { return }
		do {
			try self.session?.send(data, toPeers: [self.peerID], with: .reliable)
		} catch {
			Logger.instance.log("Error \(error) when sending to \(self.displayName)")
		}
	}
    
    open func send(file url: URL, named name: String, completion: ((Error?) -> Void)? = nil) {
        self.session?.sendResource(at: url, withName: name, toPeer: peerID, withCompletionHandler:  completion)
    }
	
	func session(didReceive data: Data) {
		guard let payload = NearbyMessagePayload(data: data) else {
			Logger.instance.log("Failed to decode message from \(data)")
			return
		}
		
		if let message = InternalRouter.instance.route(payload, from: self) {
			self.delegate?.didReceive(message: message, from: self)
		} else if let message = NearbySession.instance.messageRouter?.route(payload, from: self) {
			self.delegate?.didReceive(message: message, from: self)
		}
	}
	
	func session(didReceive stream: InputStream, withName streamName: String) {
		
	}
	
	func session(didStartReceivingResourceWithName resourceName: String, with progress: Progress) {
		
	}
	
	func session(didFinishReceivingResourceWithName resourceName: String, at localURL: URL?, withError error: Error?) {
		
	}
	
	static func ==(lhs: NearbyDevice, rhs: NearbyDevice) -> Bool {
		return lhs.peerID == rhs.peerID
	}

	func sendChanges() {
		if #available(OSX 10.15, iOS 13.0, *) {
			#if canImport(Combine)
				self.objectWillChange.send()
			#endif
		}
	}
}

extension NearbyDevice {
	struct Keys {
		static let name = "name"
		static let idiom = "idiom"
		static let unique = "unique"
	}
}

extension MCSessionState: CustomStringConvertible {
	public var description: String {
		switch self {
		case .connected: return "*conected*"
		case .notConnected: return "*notConnected*"
		case .connecting: return "*connecting*"
		@unknown default: return "*unknown*"
		}
	}
}
