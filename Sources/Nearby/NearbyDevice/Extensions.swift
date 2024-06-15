//
//  Extensions.swift
//  
//
//  Created by Ben Gottlieb on 6/13/23.
//

import Foundation
import MultipeerConnectivity

public extension String {
	var idBasedFilename: String {
		let base = self
		if base.count > 32 { return String(base[0...32]) }
		return base
	}
}


extension MCPeerID: @retroactive Identifiable {
	public var id: String {
		let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: false)
		return data?.base64EncodedString() ?? "MCPeerID"
	}
}
