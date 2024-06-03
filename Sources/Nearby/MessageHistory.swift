//
//  MessageHistory.swift
//  iOS
//
//  Created by Ben Gottlieb on 8/1/23.
//

import Foundation

class MessageHistory: ObservableObject {
	static let instance = MessageHistory()
	
	struct RecordedMessage: Identifiable {
		let id = UUID()
		let date = Date()
		let payload: NearbyMessagePayload
		let sender: NearbyDevice
		let incoming: Bool
		
		var label: String { payload.command }
	}
	
	var limit = 0
	var history: [RecordedMessage] = []
	
	@MainActor func clearHistory() {
		history = []
		objectWillChange.send()
	}
	
	func record(payload: NearbyMessagePayload, from device: NearbyDevice) {
		//logToConsole("Handling Internal: \(payload.command)", onlyWhenDebugging: true)

		if limit == 0 { return }
		
		while history.count >= limit { history.removeFirst() }
		history.append(.init(payload: payload, sender: device, incoming: true))
		DispatchQueue.main.async { self.objectWillChange.send() }
	}
	
	func record(payload: NearbyMessagePayload, to device: NearbyDevice) {
		logToConsole("Sending \(payload.command) as a \(type(of: payload)) to \(device.name)", onlyWhenDebugging: true)

		if limit == 0 { return }
		
		while history.count >= limit { history.removeFirst() }
		history.append(.init(payload: payload, sender: device, incoming: false))
		DispatchQueue.main.async { self.objectWillChange.send() }
	}
}
