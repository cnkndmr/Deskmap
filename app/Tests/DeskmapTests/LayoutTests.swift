import CoreGraphics
import Foundation
import Testing
@testable import Deskmap

/// `WindowLayout` oranları ve `Coordinates` dönüşümleri.
struct LayoutTests {

    private let area = CGRect(x: 100, y: 50, width: 1000, height: 800)

    @Test func presetRectsInArea() {
        #expect(WindowLayout.full.rect(in: area) == area)
        #expect(WindowLayout.leftHalf.rect(in: area)
                == CGRect(x: 100, y: 50, width: 500, height: 800))
        #expect(WindowLayout.rightHalf.rect(in: area)
                == CGRect(x: 600, y: 50, width: 500, height: 800))
        #expect(WindowLayout.bottomHalf.rect(in: area)
                == CGRect(x: 100, y: 450, width: 1000, height: 400))
        #expect(WindowLayout.center.rect(in: area)
                == CGRect(x: 200, y: 130, width: 800, height: 640))
    }

    @Test func rectClampsToArea() {
        // Genişlik alanın dışına taşamaz; en az %5 kalır.
        let overflow = WindowLayout(x: 0.9, y: 0, w: 0.5, h: 1).rect(in: area)
        #expect(overflow.minX == 1000)
        #expect(abs(overflow.width - 100) < 1e-9)
        let tiny = WindowLayout(x: 0, y: 0, w: 0, h: -1).rect(in: area)
        #expect(tiny.width == 50)
        #expect(tiny.height == 40)
        // Alanın tamamen dışındaki konum kenara kilitlenir.
        let outside = WindowLayout(x: 2, y: -1, w: 1, h: 1).rect(in: area)
        #expect(outside.minX == area.maxX)
        #expect(outside.minY == area.minY)
    }

    @Test func frameInitRoundTrips() {
        for preset in WindowLayout.presets {
            let rect = preset.rect(in: area)
            let back = WindowLayout(frame: rect, in: area)
            #expect(abs(back.x - preset.x) < 1e-9, "\(preset.label) x")
            #expect(abs(back.y - preset.y) < 1e-9, "\(preset.label) y")
            #expect(abs(back.w - preset.w) < 1e-9, "\(preset.label) w")
            #expect(abs(back.h - preset.h) < 1e-9, "\(preset.label) h")
        }
    }

    @Test func frameInitClamps() {
        // Alanın dışında ve alanın iki katı büyüklükte bir pencere.
        let frame = CGRect(x: -500, y: 5000, width: 3000, height: 10)
        let layout = WindowLayout(frame: frame, in: area)
        #expect(layout.x == 0)
        #expect(layout.y == 0.95)
        #expect(layout.w == 1)
        #expect(layout.h == 0.05)
    }

    @Test func frameInitWithZeroAreaFallsBackToFull() {
        let layout = WindowLayout(frame: CGRect(x: 10, y: 10, width: 100, height: 100),
                                  in: CGRect(x: 0, y: 0, width: 0, height: 800))
        #expect(layout == WindowLayout())
        #expect(layout == .full)
    }

    @Test func labels() {
        // Test sürecinde çeviri tablosu yok: İngilizce anahtar görünür.
        #expect(WindowLayout.full.label == "Full")
        #expect(WindowLayout.leftHalf.label == "Left half")
        #expect(WindowLayout.right30.label == "Right 30%")
        #expect(WindowLayout.center.label == "Center")
        #expect(WindowLayout(x: 0.2, y: 0.1, w: 0.6, h: 0.75).label == "60% × 75%")
    }

    // MARK: Coordinates

    private func screen(_ id: String, frame: CGRect) -> ScreenInfo {
        ScreenInfo(id: id, uuid: id.uppercased(), name: id, isBuiltin: id == "builtin",
                   frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20))
    }

    @Test func axRectFlipsYAgainstPrimaryScreen() {
        let primary = screen("builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let rect = CGRect(x: 10, y: 0, width: 100, height: 100)
        let ax = Coordinates.axRect(fromCocoa: rect, screens: [primary])
        #expect(ax == CGRect(x: 10, y: 980, width: 100, height: 100))
        // Birincil ekranın üst kenarı AX'te y = 0'dır.
        let top = CGRect(x: 0, y: 1030, width: 50, height: 50)
        #expect(Coordinates.axRect(fromCocoa: top, screens: [primary]).minY == 0)
    }

    @Test func axRectOnSecondaryScreenUsesPrimaryHeight() {
        let primary = screen("builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let external = screen("external", frame: CGRect(x: 1920, y: 200, width: 2560, height: 1440))
        // Birincil ekranın listede ikinci sırada olması sonucu değiştirmez.
        let rect = CGRect(x: 2000, y: 200, width: 800, height: 600)
        let ax = Coordinates.axRect(fromCocoa: rect, screens: [external, primary])
        #expect(ax == CGRect(x: 2000, y: 1080 - 800, width: 800, height: 600))
        // Yukarı uzanan harici ekranda AX y'si negatif olur.
        let high = CGRect(x: 2000, y: 1500, width: 100, height: 100)
        #expect(Coordinates.axRect(fromCocoa: high, screens: [primary, external]).minY == -520)
    }

    @Test func closeToleranceBoundary() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Coordinates.close(a, a.offsetBy(dx: 4, dy: -4)))
        #expect(Coordinates.close(a, CGRect(x: 0, y: 0, width: 104, height: 96)))
        #expect(!Coordinates.close(a, a.offsetBy(dx: 4.01, dy: 0)))
        #expect(!Coordinates.close(a, CGRect(x: 0, y: 0, width: 100, height: 105)))
        #expect(Coordinates.close(a, a.offsetBy(dx: 10, dy: 0), tolerance: 10))
    }
}

struct LayoutToolTests {

    private let area = CGRect(x: 0, y: 0, width: 5120, height: 1410)

    @Test func fixedSizeIsPlacedAtItsAnchorAndFittedToTheArea() {
        let fixed = WindowLayout(fixed: .init(width: 1400, height: 900, anchor: .center))
        #expect(fixed.rect(in: area) == CGRect(x: 1860, y: 255, width: 1400, height: 900))
        let corner = WindowLayout(fixed: .init(width: 1400, height: 900, anchor: .bottomRight))
        #expect(corner.rect(in: area) == CGRect(x: 3720, y: 510, width: 1400, height: 900))
        // Ekrandan büyük: alana sığdırılır.
        let huge = WindowLayout(fixed: .init(width: 9000, height: 3000, anchor: .topLeft))
        #expect(huge.rect(in: area) == area)
        // Önizleme ölçeği: 1 pt = 0,1 birim.
        let preview = CGRect(x: 0, y: 0, width: 512, height: 141)
        #expect(fixed.rect(in: preview, pointsPerUnit: 0.1).width == 140)
    }

    @Test func oldLayoutsDecodeWithoutFixedAndRoundTrip() throws {
        let old = try JSONDecoder().decode(WindowLayout.self,
                                           from: Data(#"{"x":0,"y":0,"w":0.5,"h":1}"#.utf8))
        #expect(old == .leftHalf && old.fixed == nil)
        let fixed = WindowLayout(fixed: .init(width: 1200, height: 800, anchor: .top))
        let back = try JSONDecoder().decode(WindowLayout.self, from: JSONEncoder().encode(fixed))
        #expect(back == fixed)
        // Oranlı düzen kodlanırken "fixed" anahtarı yazılmaz (eski sürümler okuyabilsin).
        let json = String(decoding: try JSONEncoder().encode(WindowLayout.leftHalf), as: UTF8.self)
        #expect(!json.contains("fixed"))
    }

    @Test func presetsFollowTheDisplayShape() {
        let wide = WindowLayout.presets(aspect: 5120.0 / 1440)
        #expect(wide.contains(.leftThird) && wide.contains(.centerHalf) && !wide.contains(.topHalf))
        let laptop = WindowLayout.presets(aspect: 1.6)
        #expect(laptop.contains(.topLeft) && laptop.contains(.topHalf) && !laptop.contains(.leftThird))
    }

    @Test func presetListsAreMirrorSymmetric() {
        func mirrored(_ l: WindowLayout) -> WindowLayout {
            WindowLayout(x: 1 - l.x - l.w, y: l.y, w: l.w, h: l.h)
        }
        func close(_ a: WindowLayout, _ b: WindowLayout) -> Bool {
            abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 && abs(a.w - b.w) < 1e-9 && abs(a.h - b.h) < 1e-9
        }
        for aspect in [1.6, 16.0 / 9, 5120.0 / 1440] {
            let presets = WindowLayout.presets(aspect: aspect)
            for preset in presets {
                #expect(presets.contains { close($0, mirrored(preset)) },
                        "\(preset.label) has no mirror at aspect \(aspect)")
            }
        }
    }

    @Test func gridIsFinerOnUltrawideAndSelectsCellRanges() {
        #expect(LayoutGrid.dimensions(aspect: 1.6) == (12, 8))
        #expect(LayoutGrid.dimensions(aspect: 3.56) == (24, 6))
        // 24 sütunda 8 sütun = üçte bir; ters yönde sürükleme de aynı alan.
        let third = LayoutGrid.layout(from: .init(col: 7, row: 5), to: .init(col: 0, row: 0),
                                      cols: 24, rows: 6)
        #expect(abs(third.w - 1.0 / 3) < 1e-9 && third.h == 1 && third.x == 0)
        let cell = LayoutGrid.cell(at: CGPoint(x: 999, y: -5), size: CGSize(width: 420, height: 118),
                                   cols: 24, rows: 6)
        #expect(cell == .init(col: 23, row: 0))
    }

    @Test func togglingFixedKeepsTheArea() {
        let size = CGSize(width: 1710, height: 1074)
        let on = LayoutEditor.toggledFixed(.center, on: true, screenSize: size)
        #expect(on.fixed == .init(width: 1370, height: 860, anchor: .center))
        let off = LayoutEditor.toggledFixed(on, on: false, screenSize: size)
        #expect(off.fixed == nil && abs(off.w - 1370.0 / 1710) < 1e-9)
        // Sabitleme noktası alanın dayandığı kenarlardan.
        #expect(LayoutEditor.toggledFixed(.topLeft, on: true, screenSize: size).fixed?.anchor == .topLeft)
        #expect(LayoutEditor.toggledFixed(.rightThird, on: true, screenSize: size).fixed?.anchor == .right)
        #expect(LayoutEditor.toggledFixed(.bottomHalf, on: true, screenSize: size).fixed?.anchor == .bottom)
        #expect(LayoutEditor.toggledFixed(.full, on: true, screenSize: size).fixed?.anchor == .center)
    }
}
