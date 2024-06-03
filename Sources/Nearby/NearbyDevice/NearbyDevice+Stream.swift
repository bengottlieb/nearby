//
//  NearbyDevice+Stream.swift
//  
//
//  Created by Ben Gottlieb on 8/23/23.
//

import Foundation
import MultipeerConnectivity
import CrossPlatformKit
import Studio

extension NearbyDevice: StreamDelegate {
	public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch eventCode {
		case .endEncountered:
			closeStream()
			
		default:
			break
		}
	}
}

extension NearbyDevice {
	public func startStream(named name: String = "nearby-stream") throws -> OutputStream {
		if let outgoingStream { return outgoingStream }
		guard let stream = try session?.startStream(withName: name, toPeer: peerID) else { throw NearbyDeviceError.failedToCreateStream }
		stream.delegate = self
		stream.schedule(in: RunLoop.main, forMode: .common)
		stream.open()
		
		self.bytesSent = 0
		outgoingStream = stream
		
		return stream
	}
	
	func received(streamData data: Data) {
		bytesReceived += Int64(data.count)
		receivedStreamedData?(data)
	}
	
	public func send(data: Data) throws {
		guard let outgoingStream else {
			logToConsole("No outgoing stream")
			throw NearbyDeviceError.noOutgoingStream
		}
		
		bytesSent += Int64(data.count)
		try outgoingStream.writeCountedData(data: data)
	}
	
	func session(didReceive stream: InputStream, withName streamName: String) {
		if let incomingStream {
			logToConsole("Already have a stream (\(incomingStream) for \(name)")
			return
		}
		DispatchQueue.main.async {
			self.bytesReceived = 0
			self.incomingStream = IncomingStream(stream: stream, device: self)
			self.objectWillChange.send()
		}
	}
	
	public func closeStream() {
		if outgoingStream == nil, incomingStream == nil { return }
		
		if let outgoingStream {
			outgoingStream.remove(from: RunLoop.main, forMode: .default)
			outgoingStream.close()
		}

		incomingStream?.close()
		outgoingStream = nil
		incomingStream = nil
		objectWillChange.sendOnMain()
	}
}
