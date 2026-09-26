import Foundation
import IOKit
import os

/// All service ownership and blocking DDC transactions stay on this serial queue.
final class ExternalDisplays {
    struct Display {
        let id: UInt64
        let name: String
        var hasProductName = true
    }
    struct Brightness {
        let current: Int
        let maximum: Int
    }

    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<AnyObject>?
    private typealias Transfer = @convention(c) (AnyObject, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private let queue = DispatchQueue(label: "com.ntoktok.lidlux.ddc", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var services: [UInt64: AnyObject] = [:]
    private let logger = Logger(subsystem: "com.ntoktok.lidlux", category: "ddc")

    private func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = Self.handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Immediately cancels queued work, including remaining retries of an in-flight read.
    /// An IOKit call already in progress cannot be interrupted.
    func invalidate() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        return generation
    }

    private func valid(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == token
    }

    func enumerate(token: Int, completion: @escaping ([Display]) -> Void) {
        queue.async { [self] in
            guard valid(token) else { return }
            services.removeAll()
            var displays: [Display] = []
            if let create = symbol("IOAVServiceCreateWithService", as: Create.self),
               symbol("IOAVServiceWriteI2C", as: Transfer.self) != nil,
               symbol("IOAVServiceReadI2C", as: Transfer.self) != nil {
                var iterator: io_iterator_t = 0
                if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS {
                    defer { IOObjectRelease(iterator) }
                    while case let service = IOIteratorNext(iterator), service != 0 {
                        defer { IOObjectRelease(service) }
                        guard valid(token) else { return }
                        let location = IORegistryEntryCreateCFProperty(service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                        guard location == "External" else { continue }
                        var id: UInt64 = 0
                        guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                              let av = create(kCFAllocatorDefault, service)?.takeRetainedValue() else { continue }
                        let attributes = IORegistryEntryCreateCFProperty(service, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
                        let product = attributes?["ProductAttributes"] as? [String: Any]
                        let name = product?["ProductName"] as? String
                        services[id] = av
                        displays.append(Display(id: id, name: name ?? "", hasProductName: name?.isEmpty == false))
                    }
                }
            } else {
                logger.notice("DDC API unavailable; external monitors skipped")
            }
            let result = displays.sorted { $0.id < $1.id }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func read(id: UInt64, token: Int, completion: @escaping (Brightness?) -> Void) {
        queue.async { [self] in
            let result = readBrightness(id: id, token: token)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func readBrightness(id: UInt64, token: Int) -> Brightness? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let service = services[id],
              let write = symbol("IOAVServiceWriteI2C", as: Transfer.self),
              let read = symbol("IOAVServiceReadI2C", as: Transfer.self) else { return nil }
        for attempt in 0..<4 {
            guard valid(token) else { return nil }
            var packet: [UInt8] = [0x82, 0x01, 0x10, 0]
            packet[3] = packet.prefix(3).reduce(0x6E ^ 0x51, ^)
            let sent = packet.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            usleep(50_000)
            guard valid(token) else { return nil }
            var buffer = [UInt8](repeating: 0, count: 12)
            let received = buffer.withUnsafeMutableBytes { read(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) }
            if sent == 0, received == 0, buffer[2] == 0x02, buffer[3] == 0, buffer[4] == 0x10 {
                let maximum = Int(buffer[6]) << 8 | Int(buffer[7])
                let current = Int(buffer[8]) << 8 | Int(buffer[9])
                if maximum > 0, current <= maximum { return Brightness(current: current, maximum: maximum) }
            }
            if attempt < 3 { usleep(100_000) }
        }
        return nil
    }

    func write(id: UInt64, value: Int, token: Int, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            var success = false
            if valid(token), let service = services[id],
               let write = symbol("IOAVServiceWriteI2C", as: Transfer.self), (0...65535).contains(value) {
                var packet: [UInt8] = [0x84, 0x03, 0x10, UInt8(value >> 8), UInt8(value & 0xff), 0]
                packet[5] = packet.prefix(5).reduce(0x6E ^ 0x51, ^)
                success = packet.withUnsafeMutableBytes { write(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) } == 0
                usleep(50_000)
            }
            let result = success
            DispatchQueue.main.async { completion(result) }
        }
    }
}
