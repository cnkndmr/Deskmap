# Değişiklik günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/) esas alınmıştır.

## [Yayınlanmadı]

### Düzeltildi

- Router, bu modda hedefi olmayan daha özgül bir kural yüzünden pencereyi
  atlıyordu; artık arayüzle aynı seçimi yapar (bu modda hedefi olan ilk
  eşleşen kural).
- "Yeniden yerleştir" (ve düzen belleğini sıfırlayan diğer işlemler)
  tarama sürerken basılınca etkisiz kalıyordu.
- Masaüstü taşıması tutmayan pencere için sonsuz 200 ms döngüsü; artık
  6 denemeden sonra bırakılır, pencere hedefe varınca sayaç sıfırlanır.
- Hedef ekranda tam ekran uygulama görünürken pencere tam ekran space'e
  "hop" ettirilmiyor.
- Çıkışta bekleyen (400 ms gecikmeli) kayıt diske yazılır.
- Okunamayan `rules.json` üzerine yazılmadan önce `rules.json.bak`'a
  yedeklenir.
- Kapanmış pencerelerin düzen/deneme kayıtları her taramada budanır
  (uzun süre açık kalınca bellek büyümüyor).
- Monitör takılıp çıkarılınca mod seçici gerçek modu izler; Mission
  Control'de eklenen/silinen masaüstü haritaya anında yansır.
- Accessibility'ye yanıt vermeyen (donmuş) uygulama artan sürelerle
  (2–30 sn) atlanır, alt çubukta "X yanıt vermiyor" gösterilir; böylece
  bir uygulama bütün taramayı bekletmez.
- Bozuk dosyada aktif profil bulunamayınca üretilen "Varsayılan" profil
  adı çakışırsa "Varsayılan (2)" olur.
- "Hop" kaldırıldı: görünmeyen masaüstündeki pinli pencere artık düzen
  için bulunduğun masaüstüne uğratılmıyor (o masaüstünde yabancı pencere
  belirip kayboluyor, Dock'tan uygulamaya geçişte macOS yanlış Space'e
  gidiyordu). Düzen, o masaüstüne ilk geçişte verilir.

### Eklendi

- `scripts/build-and-run.command`: Finder'dan çift tıklayınca çalışan
  Space Router'ı kapatır, derler, yeniden açar; çıktı `build/last-build.log`.

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
