//
//  AvatarCache.swift
//  EyeFull
//
//  Created by Ben Gottlieb on 8/2/23.
//

import Foundation
import CrossPlatformKit

class AvatarCache {
	static let instance = AvatarCache()
	
	var cachedAvatars: [String: CachedAvatar] = [:]
	let directory = URL.cache(named: "cached_nearby_avatars")
	
	init() {
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}
	
	func avatarInfo(forHash hash: String?) -> CachedAvatar? {
		guard let hash else { return nil }
		
		if let cached = cachedAvatars[hash] { return cached }
		
		let url = directory.appendingPathComponent(hash)
		do {
			if let data = try? Data(contentsOf: url) {
				let cache = try JSONDecoder().decode(CachedAvatar.self, from: data)
				cachedAvatars[hash] = cache
				return cache
			}
		} catch {
			logToConsole("Failed to retreive avatar info: \(error)")
		}
		return nil
	}
	
	func store(_ message: NearbySystemMessage.Avatar) {
		logToConsole("Storing avatar for \(message.hash)")
		
		let cache = CachedAvatar(image: message.image, name: message.name, hash: message.hash)
		cachedAvatars[message.hash] = cache
		
		do {
			let data = try JSONEncoder().encode(cache)
			let url = directory.appendingPathComponent(message.hash)
			try data.write(to: url)
		} catch {
			logToConsole("Failed to store avatar info: \(error)")
		}
	}
}

extension AvatarCache {
	struct CachedAvatar: Codable {
		enum CodingKeys: String, CodingKey { case name, image, hash }
		
		let image: UXImage?
		let name: String?
		let hash: String
		
		init(image: UXImage?, name: String?, hash: String) {
			self.image = image
			self.name = name
			self.hash = hash
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			
			if let data = try container.decodeIfPresent(Data.self, forKey: .image) {
				image = UXImage(data: data)
			} else {
				image = nil
			}
			
			name = try container.decodeIfPresent(String.self, forKey: .name)
			hash = try container.decode(String.self, forKey: .hash)
		}
		
		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			
			if let data = image?.pngData() {
				try container.encode(data, forKey: .image)
			}
			
			if let name { try container.encode(name, forKey: .name) }
			try container.encode(hash, forKey: .hash)
		}
	}
}
