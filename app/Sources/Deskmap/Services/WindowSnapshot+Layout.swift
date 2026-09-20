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
}
