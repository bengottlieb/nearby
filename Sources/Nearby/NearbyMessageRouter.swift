//
//  MessageRouter.swift
//
//  Created by Ben Gottlieb on 5/19/18.
//  Copyright © 2018 Stand Alone, Inc. All rights reserved.
//

import Foundation

public protocol NearbyMessageRouter {
	func route(_ payload: NearbyMessagePayload, from device: NearbyDevice) -> NearbyMessage?
	func received(dictionary: [String: String], from device: NearbyDevice)
	var fileID: String { get }
	func didDiscover(device: NearbyDevice)
	func didProvision(device: NearbyDevice)
}

extension NearbyMessageRouter {
	var moduleName: String {
		fileID.components(separatedBy: "/").first!
	}
}

class InternalRouter: NearbyMessageRouter {
	static let instance = InternalRouter()
	var fileID: String { #fileID }
	
	func didDiscover(device: NearbyDevice) { }
	func didProvision(device: NearbyDevice) { }

	func received(dictionary: [String: String], from device: NearbyDevice) { }
	
	func route(_ payload: NearbyMessagePayload, from device: NearbyDevice) -> NearbyMessage? {
		//print("message received: \(payload)")
		guard let kind = NearbySystemMessage.Kind(rawValue: payload.command) else { return nil }
		
		do {
			switch kind {
			case .ping: 
				logToConsole("PING")
			case .disconnect: device.disconnect()
			case .dictionary:
				if let message = try payload.reconstitute(NearbySystemMessage.DictionaryMessage.self) {
					NearbySession.instance.messageRouter?.received(dictionary: message.info, from: device)
					return message
				}
			
			case .requestDeviceInfo:
				device.sendDeviceInfo()
				
			case .avatar:
				if let message = try payload.reconstitute(NearbySystemMessage.Avatar.self) {
					device.avatarReceived(via: message)
					return message
				}

			case .requestAvatar:
				device.sendAvatar()

			case .deviceInfo:
				if let message = try payload.reconstitute(NearbySystemMessage.DeviceInfo.self) {
					device.deviceInfo = message.deviceInfo
					return message
				}
			}

			return try payload.reconstitute(NearbySystemMessage.self)
		} catch {
			logToConsole("Failed to reconstitute a \(payload.command) message: \(error)")
		}
		
		return nil
	}
	
}
