import CoreGraphics
import Foundation

/// 비공개 API는 헤더가 없으므로 dlsym으로 런타임에 불러온다.
private func loadSymbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let pointer = dlsym(handle, name) else { return nil }
    return unsafeBitCast(pointer, to: type)
}

/// 내장 조도 센서(ALS). Apple Silicon에서는 IOHIDEventSystem을 통해 읽는다.
final class AmbientLightSensor {
    private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    private static let eventTypeAmbientLight: Int64 = 12
    // 재생성마다 dlopen 참조 횟수가 늘지 않도록 프로세스 수명 동안 공유한다.
    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private let copyEvent: CopyEvent
    private let getFloatValue: GetFloatValue
    /// 클라이언트가 해제되면 서비스도 무효가 되므로 함께 보관한다
    private let client: AnyObject
    private let service: AnyObject

    init?() {
        let iokit = Self.iokit
        guard
            let create = loadSymbol(iokit, "IOHIDEventSystemClientCreate", as: ClientCreate.self),
            let setMatching = loadSymbol(iokit, "IOHIDEventSystemClientSetMatching", as: SetMatching.self),
            let copyServices = loadSymbol(iokit, "IOHIDEventSystemClientCopyServices", as: CopyServices.self),
            let copyEvent = loadSymbol(iokit, "IOHIDServiceClientCopyEvent", as: CopyEvent.self),
            let getFloatValue = loadSymbol(iokit, "IOHIDEventGetFloatValue", as: GetFloatValue.self),
            let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else { return nil }

        // UsagePage 0xff00 / Usage 4 = AppleVendor ambient light sensor
        setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 4] as CFDictionary)
        guard let services = copyServices(client)?.takeRetainedValue() as? [AnyObject],
              let service = services.first
        else { return nil }

        self.copyEvent = copyEvent
        self.getFloatValue = getFloatValue
        self.client = client
        self.service = service
    }

    /// 현재 조도(lux). 읽기에 실패하면 nil.
    func lux() -> Double? {
        let type = Self.eventTypeAmbientLight
        guard let event = copyEvent(service, type, 0, 0)?.takeRetainedValue() else { return nil }
        let value = getFloatValue(event, Int32(type << 16))
        return value.isFinite && value >= 0 ? value : nil
    }
}

/// 내장 디스플레이 밝기 (0.0 ~ 1.0). DisplayServices 비공개 프레임워크 사용.
final class BuiltinDisplay {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getBrightness: GetBrightness
    private let setBrightness: SetBrightness

    init?() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        guard
            let get = loadSymbol(handle, "DisplayServicesGetBrightness", as: GetBrightness.self),
            let set = loadSymbol(handle, "DisplayServicesSetBrightness", as: SetBrightness.self)
        else { return nil }
        getBrightness = get
        setBrightness = set
    }

    /// 뚜껑을 닫은 상태(클램쉘)이거나 디스플레이가 꺼져 있으면 nil.
    private var displayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    var isAvailable: Bool { displayID != nil }

    var brightness: Float? {
        guard let id = displayID else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return value
    }

    @discardableResult
    func setBrightness(_ value: Float) -> Bool {
        guard value.isFinite, let id = displayID else { return false }
        return setBrightness(id, min(max(value, 0), 1)) == 0
    }
}
