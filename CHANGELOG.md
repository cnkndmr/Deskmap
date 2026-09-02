# Değişiklik günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/) esas alınmıştır.

## [0.1.2] — 2026-09-02

### Eklendi

- Motor kendi kaynak dizinini izler; `engine/spacerouter/` içindeki bir
  `.lua` dosyası değiştiğinde Hammerspoon kendini yeniden yükler.
  Önceden `rules.json` yeniden yüklemesi Lua modüllerini tazelemediği
  için kod düzeltmeleri elle "Reload Config" yapılana kadar etkisiz
  kalıyordu.
- Menüye "Hammerspoon'u yeniden yükle (motor kodu)".

### Düzeltildi

- Atomik yazmanın ürettiği ikinci FSEvents olayı çifte yeniden
  yüklemeye yol açıyordu; yapılandırma izleyicisi debounce edildi.

## [0.1.1] — 2026-09-02

### Düzeltildi

- `hs.urlevent` geri çağrısının imzası yanlıştı; menü çubuğu
  uygulamasından gelen her komut `attempt to index a number value`
  hatası veriyordu.
- Pencere filtresi her `rules.json` kaydında yeniden kuruluyordu.
  `hs.window.filter.new()` saniyeler sürdüğü için her düzenleme
  motoru kilitliyordu. Artık yalnızca izlenen uygulama kümesi
  değiştiğinde yeniden kurulur.
- Yer tutucu ekran UUID'leri (`REPLACE-WITH-...`) sessiz bir uyarıya
  yol açıyor ve tüm kurallar ana ekrana düşüyordu.

### Eklendi

- Masaüstü sabitleme (`settings.pinSpaces`, varsayılan açık): sıra
  numarası bir kez çözülüp gerçek Space kimliğine bağlanır; aynı ekrana
  masaüstü eklenip silinmesi hedefi kaydırmaz.
- UUID karşılaştırmasında normalizasyon, ad ile yedek eşleşme ve
  "Ekran kayıtlarını doğrula" teşhis komutu.
- Uygulamada eşleşmeyen ekran kayıtları için uyarı kutusu ve tek
  düğmeyle düzeltme; menü açılışında kendiliğinden onarım.
- `settings.clampDesktopToAvailable`: istenen masaüstü yoksa var olan
  son masaüstü kullanılır ve sebebi loglanır.
- 16 yeni test (toplam 44).

## [0.1.0] — 2026-09-02

İlk sürüm.

### Eklendi

- Hammerspoon motoru: başlık tabanlı kural eşleştirme, ekran UUID
  çözümleme, dock durumuna göre docked/undocked profilleri, oransal
  layout, normal Desktop sayımı üzerinden Space taşıma.
- Uygulamadan bağımsız kural modeli: Safari Tab Group, VS Code
  workspace ve başlıkta ad gösteren diğer uygulamalar.
- `rules.json` canlı izleme ve tolerant doğrulama.
- SwiftUI menü çubuğu uygulaması: kural editörü, açık pencerelerden
  seçim, canlı eşleşme testi, ekran kaydı, izin ve motor durumu.
- `install.sh`, `uninstall.sh`, `build-app.sh`, `check.sh` ve Makefile.
- Kurulum, şema, uygulama şablonları, mimari ve sorun giderme belgeleri.
- Commit öncesi doğrulama kancası ve GitHub Actions iş akışı.
