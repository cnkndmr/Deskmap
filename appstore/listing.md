# Listing copy

Text for a download page, a GitHub release, a Homebrew cask description, or
a store listing if one ever becomes possible. Field names follow App Store
Connect so nothing has to be rewritten later. `<Name>` is the product name —
see [naming.md](../docs/naming.md); "Deskmap" is the current recommendation.

## English

**Name (30 chars max):** Deskmap
**Subtitle (30 chars max):** Windows where you left them
**Promotional text (170 chars max):**
Pin a project window to a display, a desktop and a layout once. Deskmap puts
it back every time — when it opens, when you dock, when you come back.

**Description:**

> Your windows have a place. Deskmap remembers it.
>
> Tell it once that the window with "acme-web" in its title belongs on the
> monitor, desktop 2, left half — and stop arranging it by hand. Deskmap
> puts every pinned window back where it belongs: when the app opens, when
> you plug in a monitor, when you come back from a meeting.
>
> It works by window title, so it works with the apps you already use: a VS
> Code workspace, a Safari tab group, an Obsidian vault, a terminal profile.
> No scripts, no helper program, no window manager to learn.
>
> **Pin by title.** Pick the part of the title that identifies the window —
> the project name, not the file name. Every window that matches, now and
> later, lands in the same place.
>
> **A map you can drag.** One card per display, one row per desktop, with
> the windows that are on them right now. Drag a window to another desktop
> to move it there — and to keep it there.
>
> **Two setups, one app.** Laptop alone and laptop plus monitor get separate
> targets. Plug the monitor in and everything rearranges itself.
>
> **Layouts.** Full, halves, 70/30, centred — applied once, then the window
> is yours to resize.
>
> **Profiles.** Desk, café, presentation. Switch with one click, or from
> Shortcuts, Raycast or a Focus automation.
>
> **Quiet by design.** A menu bar icon, no Dock icon, no notifications, no
> account, no network. Undo instead of confirmation dialogs.
>
> Requires macOS 13 or later and the Accessibility permission, which is how
> it reads window titles and moves windows. Nothing leaves your Mac.

**Keywords:** window,manager,spaces,desktops,display,monitor,layout,
workspace,menu bar,productivity,multi-monitor,arrange

**Category:** Productivity (secondary: Utilities)
**Support URL:** the user guide — docs/guide.md, published
**Marketing URL:** the project page
**Privacy:** no data collected. The app has no network code; window titles
stay on the Mac and are redacted in its own logs.

**What's new (0.4.0):**

> - English interface, with Turkish included.
> - Undo for unpinning, moving pins and reordering desktops.
> - Faster, quieter engine: fewer scans, no work while the Mac sleeps, and
>   windows are left alone while displays settle after a monitor change.
> - VoiceOver labels on every icon button.

## Türkçe

**Ad:** Deskmap
**Alt başlık:** Pencereler bıraktığın yerde
**Tanıtım metni:**
Bir proje penceresini bir kez ekrana, masaüstüne ve düzene pinle. Deskmap her
seferinde geri koyar — açılınca, monitörü takınca, sen dönünce.

**Açıklama:**

> Pencerelerinin bir yeri vardır. Deskmap orayı hatırlar.
>
> Başlığında "acme-web" geçen pencerenin monitörde, 2. masaüstünde, sol
> yarıda durduğunu bir kez söyle — elle yerleştirmeyi bırak. Deskmap pinli
> her pencereyi ait olduğu yere koyar: uygulama açılınca, monitörü takınca,
> toplantıdan dönünce.
>
> Pencere başlığına bakar, yani zaten kullandığın uygulamalarla çalışır: VS
> Code çalışma alanı, Safari sekme grubu, Obsidian kasası, terminal profili.
> Betik yok, yardımcı program yok, öğrenilecek pencere yöneticisi yok.
>
> **Başlıkla pinle.** Başlığın pencereyi tanımlayan parçasını seç — dosya adı
> değil, proje adı. Eşleşen her pencere, bugün de sonra da aynı yere iner.
>
> **Sürüklenebilir harita.** Her ekran için bir kart, her masaüstü için bir
> satır, üzerlerinde o an duran pencerelerle. Pencereyi başka masaüstüne
> sürükle: hem taşınır hem orada kalır.
>
> **İki kurulum, tek uygulama.** Tek başına laptop ve monitörlü laptop ayrı
> hedefler alır. Monitörü tak, her şey kendi yerine gider.
>
> **Düzenler.** Tam, yarım, %70/%30, orta — bir kez uygulanır, sonrası sana
> kalmış.
>
> **Profiller.** Masa, kafe, sunum. Tek tıkla ya da Shortcuts, Raycast, Focus
> otomasyonundan geç.
>
> **Sessiz tasarım.** Menü çubuğunda bir simge; Dock simgesi yok, bildirim
> yok, hesap yok, ağ yok. Onay diyaloğu yerine geri alma.
>
> macOS 13 ve üstü ile Erişilebilirlik izni gerekir; pencere başlıklarını
> okuması ve pencereleri taşıması bununla olur. Mac'ten hiçbir şey çıkmaz.

**Anahtar kelimeler:** pencere,yönetici,masaüstü,ekran,monitör,düzen,çalışma
alanı,menü çubuğu,verimlilik,çoklu ekran

**Kategori:** Verimlilik (ikincil: Araçlar)
**Gizlilik:** veri toplanmaz.

## Screenshots

Five frames, generated from the real interface with demo data (see
`Demo/Shots.swift`), 2880×1800 for a store listing, same images at 1×
for the web page:

| # | Frame | Caption (EN) | Caption (TR) |
|---|---|---|---|
| 1 | Map with pinned windows | Every display, every desktop, one screen | Bütün ekranlar, bütün masaüstleri, tek ekranda |
| 2 | Pin panel with title parts | Pin by what the title says | Başlığın söylediğine göre pinle |
| 3 | Layout picker | Full, halves, 70/30 — applied once | Tam, yarım, %70/%30 — bir kez |
| 4 | Profiles | Desk, café, presentation | Masa, kafe, sunum |
| 5 | Settings card / missing desktop badge | It tells you what's wrong | Neyin bozuk olduğunu söyler |
