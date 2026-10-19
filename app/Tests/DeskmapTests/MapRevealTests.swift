import AppKit
import SwiftUI
import Testing
@testable import Deskmap

/// `ui.reveal`: harita istenen pencere satırına kayıyor mu (docs/bug-tables.md,
/// C). Ekran dışında küçük bir pencerede uzun bir liste çizilir; kaydırma
/// `NSClipView`'un başlangıcından okunur. Gerçek pencereye dokunulmaz.
@MainActor
struct MapRevealTests {

    private final class Target: ObservableObject {
        @Published var window: CGWindowID?
    }

    private struct List: View {
        @ObservedObject var target: Target
        let scroll: (ScrollViewProxy, CGWindowID) -> Void

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<80, id: \.self) { index in
                            Text("Window \(index)")
                                .frame(height: 30)
                                .id(WindowAnchor(id: CGWindowID(index)))
                        }
                    }
                }
                .onChange(of: target.window) { window in
                    if let window { scroll(proxy, window) }
                }
            }
        }
    }

    /// Satır 60'ı ister, kaydırılan miktarı döndürür.
    private func scrolledOffset(_ scroll: @escaping (ScrollViewProxy, CGWindowID) -> Void) -> CGFloat {
        let target = Target()
        let hosting = NSHostingView(rootView: List(target: target, scroll: scroll))
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 300, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        target.window = 60
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        func clip(in view: NSView) -> NSClipView? {
            if let clip = view as? NSClipView { return clip }
            return view.subviews.lazy.compactMap { clip(in: $0) }.first
        }
        return clip(in: hosting)?.bounds.origin.y ?? 0
    }

    @Test func revealScrollsToWindowRow() {
        #expect(scrolledOffset { MapReveal.scroll($0, to: $1) } > 1000)
    }

    /// Eski yol: `withAnimation` içinde `scrollTo`. macOS 27.0'da hiç
    /// kaydırmıyor; başka sürümde kayarsa bilinen sorun görünmez olur.
    @Test func animatedScrollToDoesNotMove() {
        withKnownIssue("withAnimation + scrollTo does not scroll (macOS 27.0)", isIntermittent: true) {
            #expect(scrolledOffset { proxy, window in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(WindowAnchor(id: window), anchor: .center)
                }
            } > 1000)
        }
    }
}
