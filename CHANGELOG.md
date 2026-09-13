# Değişiklik günlüğü

Biçim [Keep a Changelog](https://keepachangelog.com/tr/1.1.0/) esas alınmıştır.

## [Yayınlanmadı]

### Eklendi

- `spacerouter://` URL şeması: `reapply`, `pause`, `resume`, `toggle`,
  `profile/<ad>` (ya da `profile?name=<ad>`), `next-profile`. Shortcuts
  "Open URLs", Raycast, Hammerspoon `hs.urlevent.openURL` ve terminalde
  `open` ile kullanılır. URL'ler AppKit delegate'i (`application(_:open:)`)
  üzerinden alınır; ayrıştırma saf `URLCommand.parse` işlevinde
  (`Services/URLCommands.swift`). Bilinmeyen komut/profil alt çubukta
  hata olarak gösterilir. README'de "Otomasyon" bölümü.
- Tek kopya koruması: aynı bundle kimliğiyle çalışan başka bir Space Router
  varsa yenisi Router yaratılmadan çıkar (iki yönlendirici aynı pencereleri
  çekiştirmesin).
- Birim testleri (`make test`, Swift Testing): `Rule` eşleştirme ve başlık
  parçalama, `WindowLayout`, koordinat dönüşümü, `rules.json` şema geçişleri
  (v1/v2/v3), `Document` pin/profil işlemleri, dışa/içe aktarma ve
  `Routing` hedef seçimi. CI ve `.githooks/pre-commit` testleri de çalıştırır.
- Kökte `VERSION` dosyası; `build-app.sh` ve `make-dist.sh` sürümü oradan okur
  (`VERSION=` ortam değişkeni yine önceliklidir).
- `make dist`: evrensel (arm64 + x86_64) derleme, imza, isteğe bağlı noter ve
  `build/dist/*.zip` / `.dmg` paketi (`scripts/make-dist.sh`,
  Finder için `scripts/make-dist.command`). `build-app.sh` artık `VERSION`,
  `UNIVERSAL` ve `SIGN_IDENTITY` ortam değişkenlerini tanır; sürüm 0.3.0.
- Birleşik günlük (`Services/Log.swift`, `os.Logger`, alt sistem
  `com.spacerouter.app`; kategoriler `routing`, `skylight`, `ax`, `screens`).
  Açılışta SkyLight durumu ve masaüstü taşıma yolu; her masaüstü taşıması,
  taşıma/düzen vazgeçmesi, yanıt vermeyen uygulama backoff başlangıcı/bitişi,
  ekran yatışması, uyku duraklatma/sürdürme ve oturum pini düşmesi yazılır.
  Pencere başlıkları gizli (`.private`); tarama başına kayıt yok. İzlemek için
  `log stream --predicate 'subsystem == "com.spacerouter.app"' --level info`.
- Motor yardımcılarının birim testleri (`EngineHelperTests`): backoff kararı,
  masaüstü taşıma soğuması, harici ekran sıralaması, space türü haritası ve
  saf `Router.placement`. Toplam 68 test.
- `make concurrency-check`: `-strict-concurrency=complete` ile temiz bir
  derleme yapıp uyarıları listeler (Swift 6 hazırlığı; paket ayarı değişmez,
  ayrı derleme dizini `app/.build/strict`). README "Geliştirme" bölümünde.
- `Rule` eşleştirme testleri: Türkçe İ/ı/I/i, ß–SS ve ligatür katlama
  çiftleri (eşleşmez, `lowercased()` semantiği), çözümlenen (v1/v2) kurallar,
  değişen `tokens`, tembel başlık küçültme, eşzamanlı `split`; AX izin
  anahtarı sabiti testi. Toplam 75 test.

### Değişti

- Kural ve profil mantığı (`pin`, `unpin`, `moveDesktop`, profil geçişi/kopya/
  silme, dışa/içe aktarma) `Document` üzerinde saf işlemler oldu; `Store`
  yalnızca çağırıp yayınlar ve kaydeder. Davranış aynı.
- Hedef seçimi tek yerde (`Routing.select`): Router, pencere satırı ve harita
  aynı kuralı seçer (oturum pini, yoksa bu modda hedefi olan en özgül kural).
  Düzen deneme sayımı da `Routing`'e taşındı.
- Tarama başına IPC azaltıldı, listelenen pencere kümesi ve kararlar aynı:
  pencere sunucusu (`CGWindowListCopyWindowInfo`) taramada bir kez okunur
  (2. aşama listeleme ve yaşam denetimi aynı sonuçtan türer); space türleri
  `displaySpaces` sonucundan haritalanır (pencere başına `SLSSpaceGetType`
  yerine, haritada olmayan kimlik için IPC'ye düşer); pencere başına space,
  çerçeve ve simge durumu bir kez okunup anlık görüntü, yerleşim ve
  yönlendirmede paylaşılır (eskiden yönlendirilen pencere için 2–3 kez).
- Tarama zamanlayıcısına 0,5 sn tolerans (sistem zamanlayıcıları gruplar).
- Ekranlar ya da sistem uyurken tarama durur (`screensDidSleep` /
  `willSleep`), uyanınca hemen bir tur yapılır.
- Ekran değişimi yatışırken (2,5 sn) pencereler listelenir ama taşınmaz;
  `ScreenService.isSettling`. Yatışınca eskisi gibi hepsi yeniden yerleştirilir.
- Elle taşıma (haritada sürükleme) AX öğesini son taramadaki pid ile
  doğrudan üretir; bütün uygulamaları yeniden taramak yalnızca bu yol
  tutmazsa yapılır.
- Masaüstü taşıma sınırı ve soğuma `Routing.maxMoveAttempts` /
  `Routing.moveRetryInterval` (saf `recordMoveAttempt`).
- Sıkı eşzamanlılık (`-strict-concurrency=complete`) uyarıları servislerde
  giderildi: 16 → 2 (kalan ikisi `Store.swift` deinit'inde). `SkyLight`
  `Sendable` (bütün alanlar `let`); `DropTargetPreference.defaultValue`
  `static let`; AX backoff tablosu kilit altında `nonisolated(unsafe)`;
  `kAXTrustedCheckOptionPrompt` yerine sabit anahtar; Router / ScreenService /
  WindowEvents / AccessibilityPermission deinit'inde kapatılan Timer ve
  gözlemci belirteçleri `nonisolated(unsafe)`; uyku bildirimlerinden ana
  aktöre yalnızca bildirim adı taşınır. Davranış aynı.
- `Rule.split` ayraç deseni bir kez derlenir (eskiden her çağrıda);
  `Rule.matches` parçaların küçük harfli kopyasını saklar (`tokens`
  değişince yenilenir) ve `Routing.select` başlığı pencere başına en fazla
  bir kez küçültür. Eşleme kararı aynı: `lowercased()` semantiği korunur,
  `.caseInsensitive` arama ß/SS ve ligatür çiftlerini de eşlediği için
  kullanılmadı.

### Düzeltildi

- "Girişte başlat" gerçek `SMAppService` durumunu okur: kayıt değişince ve
  her taramada yenilenir (Sistem Ayarları'ndan kapatılırsa kutu da kapanır),
  `.requiresApproval` için turuncu "Onay gerekli" bağlantısı Login Items'ı
  açar, register/unregister hataları alt çubukta gösterilir (eskiden
  `try?` ile yutuluyordu). Uygulama /Applications dışındaysa ipucu hangi
  kopyanın kaydedileceğini söyler.
- `rules.json` içinde tek bir bozuk kural (ör. `"desktop": "x"`) bütün
  dosyayı okunmaz kılıyordu; artık yalnızca o kural atlanır, alt çubukta
  "N kural okunamadı" görünür ve dosya önce `rules.json.bak`'a yedeklenir.
  Profil içe aktarma da aynı hoşgörüyle okur.
- Daha yeni bir Space Router sürümünün yazdığı `rules.json` (`version` > 3)
  eski sürümce ezilmiyor: dosya okunur, kayıt kapatılır ve alt çubukta
  uyarı gösterilir.
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
- Yanıt vermeyen uygulama backoff'u yanlış tetikleniyordu: çok pencereli ama
  yanıt veren uygulamalar (VS Code, Chrome gibi Electron/tarayıcılar)
  toplam süre 0,7 sn'yi aşınca "yanıt vermiyor" sayılıp atlanıyordu. Artık
  ölçüt tek bir AX çağrısının ≥ 0,5 sn sürmesi (donmuş uygulama ilk çağrıda
  1 sn zaman aşımına takılır) ya da emniyet için toplamın ≥ 4 sn olması.
  Süreç geneli AX yanıt süresi açılışta 1 sn'ye çekildi; `kAXWindows` ile
  gelen pencere öğeleri ~6 sn varsayılanı kullanmıyor.
- Pencere olayı gözlemcisi ana iş parçacığını kilitleyebiliyordu: uygulama
  öğesine 1 sn yanıt süresi verilir, açılışı bitmemiş uygulamalar atlanır,
  kaydı başarısız olan uygulama artan aralıkla (2 → 30 sn) yeniden denenir;
  uygulama açılınca/etkinleşince/kapanınca bekleme silinir.
- Masaüstü taşımasından vazgeçme kalıcıydı (6 denemeden sonra "Yeniden
  yerleştir"e kadar bir daha denenmiyordu); artık son denemeden 60 sn sonra
  yeni bir deneme turu açılır.
- Pencere sunucusu boş liste döndürürse (geçici hata) oturum pinleri
  düşürülmez.
- Harici ekran rol sırası (`external`, `external-2`) aynı `minX` için
  belirsizdi; sıra artık (minX, minY, UUID) ile belirlenir.

### Eklendi

- macOS ayarları kartı: "Automatically rearrange Spaces", "switch to a
  Space with open windows", "Group windows by application", "Displays have
  separate Spaces" canlı denetlenir; yanlış olan varsa kart kapanmaz,
  "Desktop & Dock'u aç" düğmesi ilgili bölmeyi açar. Dock "Assign To: None"
  hatırlatması "Anladım" ile gizlenir (`setupNoticeDismissed`). README'de
  "Gerekli macOS ayarları" bölümü.
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
