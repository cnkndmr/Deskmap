import CoreGraphics
import Foundation

extension Router.WindowSnapshot {

    /// Pencerenin şu anki çerçevesi, bulunduğu ekranın kullanılabilir alanına
    /// göre oranlar. Pencerenin yeri bilinmiyorsa (tam ekran, taranmamış)
    /// `fallbackScreen` alınır. Çerçeve yoksa ya da ekran listede yoksa nil:
    /// çağıran ya vazgeçer ya da `.full` gibi bir varsayılan seçer.
    ///
    /// Pin bu oranları saklar; başka ekrana taşınsa da aynı oranlar orada
    /// uygulanır, çözünürlük değişse de aynı yere oturur.
    func currentLayout(screens: [ScreenInfo], fallbackScreen: String? = nil) -> WindowLayout? {
        guard let frame,
              let screenID = placement?.screen ?? fallbackScreen,
              let screen = screens.first(where: { $0.id == screenID })
        else { return nil }
        let area = Coordinates.axRect(fromCocoa: screen.visibleFrame, screens: screens)
        return WindowLayout(frame: frame, in: area)
    }

    /// Kayıtlı düzenin türüne göre şu anki düzen: oranlı kayıtta oranlar;
    /// sabit boyutlu kayıtta pencere kayıtlı yerindeyse kaydın kendisi,
    /// değilse şu anki boyut (pt) ve dayandığı kenarlardan sabitleme.
    func currentLayout(like stored: WindowLayout, screens: [ScreenInfo],
                       fallbackScreen: String? = nil) -> WindowLayout? {
        guard stored.fixed != nil else {
            return currentLayout(screens: screens, fallbackScreen: fallbackScreen)
        }
        guard let frame,
              let screenID = placement?.screen ?? fallbackScreen,
              let screen = screens.first(where: { $0.id == screenID })
        else { return nil }
        let area = Coordinates.axRect(fromCocoa: screen.visibleFrame, screens: screens)
        return Self.fixedLayout(frame: frame, stored: stored, area: area)
    }

    /// Sabit boyutlu karşılık (saf): kayıtlı yerindeyse kayıt; değilse
    /// çerçeve boyutu (tam pt) ve kenarlardan sabitleme.
    static func fixedLayout(frame: CGRect, stored: WindowLayout, area: CGRect) -> WindowLayout {
        if Coordinates.close(frame, stored.rect(in: area)) { return stored }
        // Kenara dayanıyorsa sabitleme oradan; hiçbir kenara dayanmıyorsa
        // kayıtlı sabitleme korunur (konum sabitlemeyle belirlenir).
        let touching = WindowLayout.Anchor.touching(frame, in: area)
        let anchor = touching == .center ? (stored.fixed?.anchor ?? .center) : touching
        return WindowLayout(fixed: .init(width: Double(frame.width.rounded()),
                                         height: Double(frame.height.rounded()), anchor: anchor),
                            screenSize: area.size)
    }
}
