//
//  NearbyDevice+Types.swift
//  
//
//  Created by Ben Gottlieb on 6/13/23.
//

import Foundation
import MultipeerConnectivity
import CrossPlatformKit
import Studio

extension NearbyDevice {
	enum NearbyDeviceError: Error { case failedToCreateStream, noOutgoingStream }

	struct Keys {
		static let name = "name"
		static let idiom = "idiom"
		static let unique = "unique"
		static let deviceRawType = "device"
		static let simulator = "sim"
		static let avatarHash = "avatar"
	}
}

extension MCSessionState: @retroactive CustomStringConvertible {
	public var description: String {
		switch self {
		case .connected: return "*connected*"
		case .notConnected: return "*notConnected*"
		case .connecting: return "*connecting*"
		@unknown default: return "*unknown*"
		}
	}
}

extension NearbyDevice {
	public struct Notifications {
		public static let deviceChangedState = Notification.Name("device-state-changed")
		public static let deviceConnected = Notification.Name("device-connected")
		public static let deviceProvisioned = Notification.Name("device-provisioned")
		public static let deviceDisconnected = Notification.Name("device-disconnected")
		public static let deviceChangedInfo = Notification.Name("device-changed-info")
	}
	
	public static let localDevice = NearbySession.deviceClass.init(asLocalDevice: true)
	
	public var stateColor: UXColor {
		state.color
	}
	
	public enum State: Int, Comparable, CustomStringConvertible, RawCodable { case none, hidden, found, invited, connecting, connected, provisioned, disconnected
		
		public var canConnect: Bool {
			switch self {
			case .none, .found, .disconnected, .hidden: return true
			default: return false
			}
		}
		
		public var description: String {
			switch self {
			case .none: return "None"
			case .found: return "Found"
			case .invited: return "Invited"
			case .connected: return "Connected"
			case .provisioned: return "Provisioned"
			case .connecting: return "Connecting"
			case .disconnected: return "Disconnected"
			case .hidden: return "Hidden"
			}
		}
		
		public var color: UXColor {
			switch self {
			case .none: return .gray
			case .disconnected: return .red
			case .found: return .orange
			case .invited: return .yellow
			case .connecting: return .green
			case .connected: return .blue
			case .provisioned: return .purple
			case .hidden: return .black
			}
		}
		
		public var isConnected: Bool {
			switch self {
			case .connected, .provisioned: return true
			default: return false
			}
		}
		
		public var contrastingColor: UXColor {
			switch self {
			case .found, .invited, .connected, .provisioned: return .black
			default: return .white
			}
		}
		
		public static func < (lhs: State, rhs: State) -> Bool { return lhs.rawValue < rhs.rawValue }

	}
}
