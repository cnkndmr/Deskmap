import Foundation
import AppKit
import MachO
import ObjectiveC

/// macOS'un Space (masaüstü) yönetimi için özel (private) SkyLight
/// çağrıları. Hammerspoon ve yabai'nin kullandığı yöntemlerin aynısı;
/// ek bir program gerekmeden doğrudan bu uygulamadan çağrılır.
///
/// Tüm işlevler `dlsym` ile çalışma anında çözülür; bulunamayan bir
/// simge uygulamayı çökertmez, ilgili işlem sessizce atlanır.
final class SkyLight {

    static let shared = SkyLight()

    struct Space: Equatable {
        let id: UInt64
        /// 0 = normal masaüstü, 4 = tam ekran uygulama.
        let type: Int
        var isUserSpace: Bool { type == 0 }
    }

    struct DisplaySpaces {
        let displayUUID: String
        let current: UInt64
        let spaces: [Space]
        var desktops: [Space] { spaces.filter(\.isUserSpace) }
    }

    // MARK: - Simgeler

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn =
        @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn =
        @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceGetTypeFn = @convention(c) (Int32, UInt64) -> Int32
    private typealias MoveWindowsFn =
        @convention(c) (Int32, CFArray, UInt64) -> Int32
    private typealias SetCompatIDFn = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias SetWindowListWorkspaceFn =
        @convention(c) (Int32, UnsafePointer<UInt32>, Int32, Int32) -> Int32
    private typealias BridgedOperationFn = @convention(c) (AnyObject) -> Int64
    private typealias MsgSendInitFn =
        @convention(c) (AnyObject, Selector, CFArray, UInt64) -> AnyObject?

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
    private let copySpacesForWindows: CopySpacesForWindowsFn?
    private let spaceGetType: SpaceGetTypeFn?
    private let moveWindowsToManagedSpace: MoveWindowsFn?
    private let spaceSetCompatID: SetCompatIDFn?
    private let setWindowListWorkspace: SetWindowListWorkspaceFn?
    private let performBridgedOperation: BridgedOperationFn?

    let isAvailable: Bool

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    private init() {
        let handle = dlopen(Self.frameworkPath, RTLD_NOW)

        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        let mainConnection = symbol("SLSMainConnectionID", as: MainConnectionFn.self)
        connection = mainConnection?() ?? 0

        copyManagedDisplaySpaces = symbol(
            "SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self)
        copySpacesForWindows = symbol(
            "SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)
        spaceGetType = symbol("SLSSpaceGetType", as: SpaceGetTypeFn.self)
        moveWindowsToManagedSpace = symbol(
            "SLSMoveWindowsToManagedSpace", as: MoveWindowsFn.self)
        spaceSetCompatID = symbol("SLSSpaceSetCompatID", as: SetCompatIDFn.self)
        setWindowListWorkspace = symbol(
            "SLSSetWindowListWorkspace", as: SetWindowListWorkspaceFn.self)

        // macOS 26.4+ : dışa açık olmayan simge; Mach-O sembol tablosundan bulunur.
        if let pointer = MachOSymbols.find(
            image: Self.frameworkPath,
            symbol: "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperation"
                + "P47SLSAsynchronousBridgedWindowManagementOperation") {
            performBridgedOperation = unsafeBitCast(
                pointer, to: BridgedOperationFn.self)
        } else {
            performBridgedOperation = nil
        }

        isAvailable = mainConnection != nil
            && copyManagedDisplaySpaces != nil
            && copySpacesForWindows != nil
    }

    // MARK: - Okuma

    /// Ekran başına masaüstü listesi. Anahtar: ekran UUID'si.
    /// `mainUUID`: "Displays have separate Spaces" kapalıyken macOS ekranı
    /// "Main" olarak adlandırır; bu durumda birincil ekranın UUID'si kullanılır.
    func displaySpaces(mainUUID: String?) -> [DisplaySpaces] {
        guard let fn = copyManagedDisplaySpaces,
              let array = fn(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return array.compactMap { entry in
            guard var uuid = entry["Display Identifier"] as? String else {
                return nil
            }
            if uuid == "Main", let mainUUID { uuid = mainUUID }

            let current = (entry["Current Space"] as? [String: Any])?["id64"]
            let spaces = (entry["Spaces"] as? [[String: Any]] ?? []).compactMap {
                space -> Space? in
                guard let id = Self.uint64(space["id64"]) else { return nil }
                let type = (space["type"] as? NSNumber)?.intValue ?? 0
                return Space(id: id, type: type)
            }
            return DisplaySpaces(
                displayUUID: ScreenInfo.normalize(uuid),
                current: Self.uint64(current) ?? 0,
                spaces: spaces)
        }
    }

    /// Pencerenin bulunduğu space kimlikleri.
    func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard let fn = copySpacesForWindows else { return [] }
        let list = [NSNumber(value: windowID)] as CFArray
        // 0x7: kullanıcı + diğer + geçerli space'ler
        guard let result = fn(connection, 0x7, list)?.takeRetainedValue()
                as? [NSNumber] else { return [] }
        return result.map(\.uint64Value)
    }

    func type(of space: UInt64) -> Int {
        Int(spaceGetType?(connection, space) ?? 0)
    }

    /// `displaySpaces` sonucundan space kimliği → türü haritası. Bir tarama
    /// boyunca `type(of:)` IPC'si yerine bu harita kullanılır; listede
    /// olmayan (nadir) kimlikler için `type(of:)` çağrılır.
    static func spaceTypes(of displays: [DisplaySpaces]) -> [UInt64: Int] {
        var types: [UInt64: Int] = [:]
        for display in displays {
            for space in display.spaces where types[space.id] == nil {
                types[space.id] = space.type
            }
        }
        return types
    }

    // MARK: - Taşıma

    /// Bu macOS'ta `move(window:to:)` hangi yolu kullanır (yalnızca günlük için).
    var movePath: String {
        if performBridgedOperation != nil,
           NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation") != nil {
            return "SLSBridgedMoveWindowsToManagedSpaceOperation"
        }
        if Self.needsCompatIDWorkaround, spaceSetCompatID != nil, setWindowListWorkspace != nil {
            return "SLSSpaceSetCompatID + SLSSetWindowListWorkspace"
        }
        if moveWindowsToManagedSpace != nil { return "SLSMoveWindowsToManagedSpace" }
        return "yok"
    }

    /// macOS 12.7 / 13.6 / 14.5 ve sonrası `SLSMoveWindowsToManagedSpace`
    /// yerine CompatID yöntemini gerektirir.
    private static let needsCompatIDWorkaround: Bool = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return (version.majorVersion == 12 && version.minorVersion >= 7)
            || (version.majorVersion == 13 && version.minorVersion >= 6)
            || (version.majorVersion == 14 && version.minorVersion >= 5)
            || version.majorVersion >= 15
    }()

    /// Pencereyi verilen masaüstüne taşır. Sonuç doğrulanmaz; çağıran
    /// `spaces(of:)` ile kontrol edebilir. Hiçbir taşıma yolu yoksa false.
    @discardableResult
    func move(window windowID: CGWindowID, to space: UInt64) -> Bool {
        var wid = windowID
        let list = [NSNumber(value: windowID)] as CFArray

        if let perform = performBridgedOperation,
           let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
           let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc")),
           let msgSend = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") {
            let initFn = unsafeBitCast(msgSend, to: MsgSendInitFn.self)
            let object = allocated.takeRetainedValue()
            if let operation = initFn(
                object, NSSelectorFromString("initWithWindows:spaceID:"),
                list, space) {
                _ = perform(operation)
                return true
            }
        }

        if Self.needsCompatIDWorkaround,
           let setCompat = spaceSetCompatID,
           let setWorkspace = setWindowListWorkspace {
            let tag: Int32 = 0x7961_6265
            _ = setCompat(connection, space, tag)
            _ = setWorkspace(connection, &wid, 1, tag)
            _ = setCompat(connection, space, 0)
            return true
        }

        if let move = moveWindowsToManagedSpace {
            _ = move(connection, list, space)
            return true
        }
        return false
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}

// MARK: - Mach-O sembol arama

/// Yüklü bir kütüphanenin sembol tablosunda dışa açık olmayan (local)
/// bir işlevi bulur. `dlsym` yalnızca dışa açık simgeleri görür.
enum MachOSymbols {

    static func find(image imagePath: String, symbol name: String)
        -> UnsafeMutableRawPointer? {

        for index in 0..<_dyld_image_count() {
            guard let cName = _dyld_get_image_name(index),
                  String(cString: cName) == imagePath,
                  let header = _dyld_get_image_header(index) else { continue }

            let slide = _dyld_get_image_vmaddr_slide(index)
            return header.withMemoryRebound(
                to: mach_header_64.self, capacity: 1) { header64 in
                search(header: header64, slide: slide, symbol: name)
            }
        }
        return nil
    }

    private static func search(
        header: UnsafePointer<mach_header_64>,
        slide: Int,
        symbol: String
    ) -> UnsafeMutableRawPointer? {
        var linkedit: UnsafePointer<segment_command_64>?
        var symtab: UnsafePointer<symtab_command>?

        var cursor = UnsafeRawPointer(header) + MemoryLayout<mach_header_64>.size
        for _ in 0..<Int(header.pointee.ncmds) {
            let command = cursor.assumingMemoryBound(to: load_command.self)
            switch command.pointee.cmd {
            case UInt32(LC_SEGMENT_64):
                let segment = cursor.assumingMemoryBound(to: segment_command_64.self)
                let segname = withUnsafePointer(to: segment.pointee.segname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 16) {
                        String(cString: $0)
                    }
                }
                if segname == SEG_LINKEDIT { linkedit = segment }
            case UInt32(LC_SYMTAB):
                symtab = cursor.assumingMemoryBound(to: symtab_command.self)
            default:
                break
            }
            cursor += Int(command.pointee.cmdsize)
        }

        guard let linkedit, let symtab else { return nil }

        let base = Int(linkedit.pointee.vmaddr) - Int(linkedit.pointee.fileoff) + slide
        guard let strings = UnsafeRawPointer(bitPattern: base + Int(symtab.pointee.stroff)),
              let symbols = UnsafeRawPointer(bitPattern: base + Int(symtab.pointee.symoff))
        else { return nil }

        let entries = symbols.assumingMemoryBound(to: nlist_64.self)
        for i in 0..<Int(symtab.pointee.nsyms) {
            let entry = entries[i]
            let namePointer = (strings + Int(entry.n_un.n_strx))
                .assumingMemoryBound(to: CChar.self)
            if entry.n_value != 0, strcmp(namePointer, symbol) == 0 {
                return UnsafeMutableRawPointer(bitPattern: Int(entry.n_value) + slide)
            }
        }
        return nil
    }
}
