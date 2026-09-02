# Değişiklik günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/) esas alınmıştır.

## [0.2.0] — 2026-09-02

Baştan sadeleştirme: tek uygulama, görsel arayüz.

### Değişti

- Hammerspoon motoru kaldırıldı. Pencere okuma/taşıma Accessibility
  API'si, Space taşıma ise SkyLight'ın özel çağrılarıyla (Hammerspoon ve
  yabai'nin kullandıklarının aynısı) doğrudan uygulama içinde yapılır.
  macOS 12.7 – 26.x arası yöntem farkları sürüme göre seçilir.
- Kural editörü, ayarlar ve ekran sekmeleri yerine tek bir ekran
  haritası: ekranlar ve masaüstleri kutu olarak çizilir, kurallar çip
  olarak sürüklenir. Düzen çipe tıklanarak görsel olarak seçilir.
- Kural ekleme: açık pencereler listesinden seçim, ardından başlığın
  parçalarını tıklayarak işaretleme. Metin girişi yok.
- Ayarlar kaldırıldı: gecikmeler, log seviyesi, sabitleme, bildirim,
  takip. Yalnızca açık/kapalı ve "Girişte başlat" kaldı.
- `rules.json` v2 şeması (`appName`, `bundleID`, `tokens`, `docked`,
  `undocked`). v1 dosyalar otomatik okunur.
- Ekranlar UUID yerine role göre tanımlanır: `builtin`, `external`,
  `external-2`…

### Kaldırıldı

- `engine/`, `install.sh`, `uninstall.sh`, `check.sh`, Lua testleri,
  `config/`, `docs/`.

## [0.1.2] — 2026-09-02

### Eklendi

- Motor kendi kaynak dizinini izler; `.lua` değişince Hammerspoon
  kendini yeniden yükler.

## [0.1.1] — 2026-09-02

### Düzeltildi

- `hs.urlevent` geri çağrısı, pencere filtresi kilitlenmesi, yer tutucu
  ekran UUID'leri.

### Eklendi

- Masaüstü sabitleme, UUID normalizasyonu, ekran kaydı onarımı.

## [0.1.0] — 2026-09-02

İlk sürüm: Hammerspoon motoru + SwiftUI kural editörü.
