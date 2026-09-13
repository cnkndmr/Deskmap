import CoreGraphics
import Foundation
import Testing
@testable import SpaceRouter

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
