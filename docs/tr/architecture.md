# Deskmap mimarisi

Bu belge uygulamanın nasıl kurulduğunu anlatır: ana türler, bir taramada
neler olduğu, yeniden deneme sınırları, veri dosyaları ve yerelleştirmenin
nasıl çalıştığı. Kullanım için [README](../../README.md)’ye bak.

## Genel bakış {#overview}

Deskmap, SwiftUI ile yazılmış bir `MenuBarExtra` uygulamasıdır (`LSUIElement`,
Dock’ta simgesi yok). Swift paketi olarak derlenir (`app/Package.swift`,
macOS 13+) ve `scripts/build-app.sh` onu bir `.app` içine sarar. Xcode projesi
yoktur.

```
main actor
  rules.json <-> Store ----- document -----> Views (RootView, ScreenMapView, panels)
                   ^                               |
                   +------ pins, profiles ---------+  (kullanıcı eylemleri)
                   |
                 Router <--- ScreenService (ekranlar, yatışma)
                   |    <--- WindowEvents  (AX gözlemcileri, NSWorkspace bildirimleri)
                   v
background queue
  sweep: SkyLight (masaüstleri) + AX (pencereler) -> Routing.select -> düzen + masaüstü taşıma
```

- `AppModel` üç temel nesneyi bir kez oluşturur (`Store`, `ScreenService`,
  `Router`). SwiftUI `App` bunları `StateObject` olarak tutar; `AppDelegate`
  URL komutlarını çalıştırmak için aynı örnekleri kullanır.
- `SingleInstance.exitIfAlreadyRunning()`, router oluşturulmadan önce çalışır:
  aynı bundle ID ile çalışan başka bir süreç varsa yeni açılan kapanır.

## Ana türler {#main-types}

| Tür | Dosya | Görevi |
|---|---|---|
| `Rule` | `Models/Rule.swift` | Bir sabitleme: `appName`, `bundleID`, `tokens` (başlık parçaları) ve her `Mode` için isteğe bağlı bir `Destination`. Eşleştirme ve başlığı parçalara ayırma burada. |
| `Destination` | `Models/Rule.swift` | Ekran rolü (`builtin`, `external`, `external-2`, …), masaüstü numarası (1’den başlar) ve `WindowLayout`. |
| `WindowLayout` | `Models/Rule.swift` | Ekranın kullanılabilir alanının kesirleri (`x`, `y`, `w`, `h`, 0…1); `leftHalf` gibi hazır düzenler. |
| `Mode` | `Models/Rule.swift` | `docked` (harici ekran bağlı) ya da `undocked`. |
| `Document` | `Models/Store.swift` | `rules.json`’ın içeriği: etkin profilin kuralları, bütün profiller, bilinen ekranlar, açma/kapama anahtarı. Kural ve profil işlemlerinin hepsi bunun üzerindeki saf `mutating` fonksiyonlardır. |
| `Store` | `Models/Store.swift` | `Document`’ı tutan `ObservableObject`: onu kaydeder (400 ms gecikmeyle, çıkışta hemen), hataları alt çubuğa bildirir ve geri alma kayıtlarını tutar. |
| `ChangeHistory` | `Models/ChangeHistory.swift` | Oturum boyunca ayar değişikliklerinin zaman çizelgesi: açılıştaki durum, en çok 50 kayıt (öncesi/sonrası belge; geçici sabitlemeler gibi belge dışındaki durum için isteğe bağlı bir closure, bu da kaydı yalnız geri alınabilir yapar) ve bir imleç. Geri al, yinele, herhangi bir satıra dön; geri aldıktan sonra yapılan yeni bir değişiklik yineleme dalını atar, ama bir sonraki değişikliğe kadar saklar, böylece Geri al onu geri getirebilir. Etiketsiz yapılan değişiklikler (URL komutu, CLI, profil değiştirme) `Store`’un `didSet`’inde kayda dönüşür; gürültü (duraklatma anahtarı, ekranlar, ad önbellekleri, profil eşitleme) dönüşmez. Kaydedilmez. |
| `Router` | `Services/Router.swift` | Motor. Taramalar, geçici sabitlemeler (`sessionPins`), elle yapılan tek seferlik taşımalar. |
| `Routing` | `Services/Routing.swift` | Saf yardımcılar: `select` bir pencerenin hedefini seçer (hem motor hem arayüz kullanır); ayrıca düzen ve taşıma denemelerinin sayımı. |
| `AX` | `Services/Accessibility.swift` | Pencereleri listeleme, çerçeveler, `setFrame`, yanıt vermeyen uygulamalar için geri çekilme (backoff). `AccessibilityPermission` güven durumunu yoklar. |
| `SkyLight` | `Services/SkyLight.swift` | Özel Spaces API’si: ekran başına masaüstleri, bir pencerenin Alan’ları, bir pencereyi bir Alan’a taşıma. |
| `MoveHealth` / `MoveSupport` | `Services/MoveHealth.swift`, `Services/MoveSupport.swift` | Saf: her masaüstü taşıması sonraki taramada denetlenir, art arda başarısızlık devre kesiciyi açar (düşük mod); taşımanın doğrulanmadığı macOS sürümlerinde (15.x, 26.0–26.3) kullanıcı **Yine de dene** diyene kadar taşıma bekletilir. |
| `ScreenService` | `Services/ScreenService.swift` | Rolleriyle birlikte bağlı ekranlar; ekranlar yeniden düzenlenirken `isSettling`. |
| `WindowEvents` | `Services/WindowEvents.swift` | Uygulama başına AX gözlemcileri ve çalışma alanı (workspace) bildirimleri; bir tarama tetikleyen sinyal yayımlar. |
| `URLCommand` / `URLCommands` | `Services/URLCommands.swift` | `deskmap://` URL’leri için saf ayrıştırıcı ve onları çalıştıran kod. |
| `MacSettings` | `Services/MacSettings.swift` | macOS ayarları kartı için Dock/Spaces tercihlerini okur. |
| `UIState` | `Views/UIState.swift` | Görünüm durumu: açık olan tek alt panel (`BottomPanel`), sürükleme durumu, pencere anlık görüntüsü, masaüstü sayıları. |

## Tarama {#the-sweep}

Tarama (sweep) şunlarla tetiklenir:

- 2 sn’de bir yinelenen bir zamanlayıcı (0,5 sn tolerans),
- 80 ms gecikmeyle toplanan pencere olayları: pencere oluşturuldu, odaktaki
  pencere değişti, küçültülmüş pencere geri açıldı, başlık değişti, uygulama
  açıldı ya da etkinleşti, etkin Alan değişti,
- etkin kurallarda bir değişiklik (yeni sabitleme, profil değiştirme, …),
- bir değişiklikten sonra ekranların yatışması,
- ⌘R / ↻ / `deskmap://reapply`; bunlar düzen belleğini de temizler.

Erişilebilirlik izni yoksa tarama hiçbir şey yapmaz. Ekranlar ya da sistem
uyurken durur (uyanınca hemen sürer; uyanma bildirimi kaçırılırsa
zamanlayıcıdaki bir güvenlik denetimi onu yeniden başlatır). Bir tarama zaten
çalışıyorsa bir tane daha sıraya alınır.

Router’ın arka plan kuyruğundaki adımlar:

1. **Ekranlar ve masaüstleri**: `SkyLight.displaySpaces` her ekranın
   Alan’larını ve görünür olanı döndürür. Alan türleri bu listeden gelir
   (0 = normal masaüstü, başka bir değer = tam ekran).
2. **Pencere sunucusu listesi**: `CGWindowListCopyWindowInfo` bir kez okunur.
   İki işe yarar: aşağıdaki 2. aşama pencere listesi ve geçici sabitlemeler
   için “bu pencere hâlâ var mı” denetimi.
3. **Pencereler (Erişilebilirlik)**:
   - 1. aşama: her normal uygulamanın kendi `kAXWindows` listesi (görünür
     masaüstü için güvenilir).
   - 2. aşama: uygulamanın listelemediği pencereler (başka masaüstlerinde ya
     da ekranlarda) pencere sunucusu listesinden alınır (katman 0, saydam
     değil, en az 50 pt) ve `_AXUIElementCreateWithRemoteToken` ile AX
     öğelerine çevrilir.
   - Yüzen paneller, sistem iletişim kutuları ve bilinmeyen alt roller atlanır.
   - Her uygulamanın AX çağrılarının süresi ölçülür. Tek bir çağrı 0,5 sn ya
     da daha uzun sürerse veya toplam 4 sn’yi bulursa uygulama geri çekilmeye
     alınır (2 sn, iki katına çıkarak en çok 30 sn); alt çubuk onu yanıt
     vermiyor olarak listeler.
4. **Pencere başına durum**: Alan’lar, tam ekran işareti, çerçeve ve küçültülme
   durumu bir kez okunur; arayüz anlık görüntüsü ve aşağıdaki yönlendirme
   aynı veriyi paylaşır.
5. **Yönlendirme**, her pencere için:
   - `Routing.select`: geçici sabitleme kazanır; yoksa eşleşen kurallar
     arasında en özgül olan (en çok başlık parçası olan) **ve şu anki
     planda hedefi olan** seçilir.
   - Hedef ekran bağlı değilse ya da pencere tam ekran bir Alan’daysa atlanır.
   - Masaüstü numarası, ekranın masaüstü sayısıyla sınırlanır.
   - **Düzen** (yalnız pencere görünür bir masaüstündeyse, küçültülmemişse ve
     bu pencere/hedef çifti için düzen henüz uygulanmadıysa): çerçeveyi yaz,
     geri oku, 4 pt içindeyse kabul et. En çok 6 deneme; ilk 4’ü hızlı bir
     ek tarama planlar (200 ms). Çerçeve yazımlarına 3 sn AX zaman aşımı
     verilir; okumalar süreç genelindeki 1 sn zaman aşımını kullanır.
   - **Masaüstü**: pencere hedef Alan’da değilse SkyLight ile taşınır. En çok
     6 deneme; ardından son denemeden 60 sn sonra yeni bir tur başlar. Pencere
     yerine varınca sayaç sıfırlanır.
6. **Yeniden main actor’da**: kapanmış pencerelerin düzen ve deneme kayıtları
   temizlenir; penceresi art arda 3 taramada pencere sunucusunda görünmeyen
   geçici sabitlemeler bırakılır; arayüz anlık görüntüsü ve alt çubuk durumu
   (son işlem, yanıt vermeyen uygulamalar) yayımlanır.

Pencere sunucusu boş bir liste döndürürse (geçici bir hata), hiçbir şey
temizlenmez ve hiçbir geçici sabitleme bırakılmaz.

### Ekran değişiklikleri {#display-changes}

`didChangeScreenParametersNotification` geldiğinde `ScreenService` ekranları
yatışıyor olarak işaretler. Taramalar pencereleri listelemeyi sürdürür ama
hiçbir şeyi taşımaz. 2,5 sn boyunca başka değişiklik olmazsa, ya da en geç
ilk değişiklikten 10 sn sonra, ekranlar yatışmış sayılır ve her pencere
yeniden yerine konur.

İlk bildirimden plan uygulanana kadar değişiklik bir *geçiş*tir: bu sırada
kaybolan bir masaüstü silinmiş sayılmaz. Yatışmadan sonra `Succession` (R2),
kaybolan her masaüstünün ardılını tuttuğu pencerelere bakarak bulur; ardından
`PlanApply.compute` (saf) profilin yeni kurulum için planını oluşturma,
taşıma, yeniden bağlama ve kaldırma adımlarına çevirir, router da bunları bu
sırayla yürütür (oluşturma ve kaldırma için Mission Control, taşıma için
SkyLight; her adım doğrulanır, ekran kuşağı değişirse iptal edilir, üst sınır
30 sn). Yalnız plan uzunluğunu aşan boş artık masaüstleri kaldırılır; her
kaldırmadan hemen önce yeniden denetlenir. Sonuç ve günlük
`desktop-state.json`’a yazılır. Belirtim: şema 6 tasarım notları
(desktop-names-v2, deponun dışında tutuluyor).

Harici ekran rolleri `DisplayRoles`’tan gelir (`Models/DisplayRoles.swift`,
saf): UUID’si bir rol için hatırlanan ekran o rolü alır (aynı rolde iki ekran
hatırlanıyorsa en son kullanılan kazanır); kalanlar konum sırasıyla (`minX`,
sonra `minY`, sonra UUID) en küçük boş rollere oturur. Hiç kayıt yoksa bu eski
konum sırasıdır. `AppModel` iki yanı eşit tutar: belgedeki `displayRoles`
`ScreenService.roles`’a gider, yatışmış her ekran listesi belgeye öğretilir
(yatışırken değil, test ekranı hiç). Monitörlü sabitlemenin sıralı yerleri
vardır (`Rule.docked` + `dockedNext`); `Routing.resolvePlace`
(`Router.resolvePlaces` sarar) bağlı ve onay beklemeyen bir ekrandaki ilk
yeri, yoksa rol sırasında bağlı ilk harici ekranı ilk yerin masaüstü
numarasıyla seçer. Uygulanan anahtar çözülmüş hedefe bağlı olduğu için
monitör geri gelince sabitleme yeniden yerleşir. Dahili ekran her zaman
`builtin`’dir.

### Pencereleri masaüstleri arasında taşıma {#moving-windows-between-desktops}

`SkyLight.move(window:to:)` sırayla şunları dener:

1. Dışa aktarılmamış `SLSPerformAsynchronousBridgedWindowManagementOperation`
   ile birlikte `SLSBridgedMoveWindowsToManagedSpaceOperation` (macOS 26.4+);
   Mach-O sembol tablosu üzerinden bulunur (`MachOSymbols`).
2. `SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace` (macOS 12.7, 13.6,
   14.5 ve sonrası).
3. `SLSMoveWindowsToManagedSpace` (daha eski sürümler).

Seçilen yol açılışta bir kez günlüğe yazılır (`skylight` kategorisi).

## Veri dosyaları {#data-files}

Bütün dosyalar `~/Library/Application Support/Deskmap/` içinde durur.

### rules.json (şema sürümü 6) {#rulesjson-schema-version-6}

```json
{
  "version": 6,
  "enabled": true,
  "activeProfileID": "…",
  "setupNoticeDismissed": false,
  "screens": [
    { "id": "builtin",  "name": "Built-in Retina Display", "aspect": 1.54 },
    { "id": "external", "name": "External Monitor",        "aspect": 1.78 }
  ],
  "rules": [
    {
      "id": "…",
      "appName": "Code",
      "bundleID": "com.microsoft.VSCode",
      "tokens": ["Deskmap"],
      "docked":   { "nameID": "N-Nova", "screen": "external", "desktop": 2,
                    "layout": { "x": 0, "y": 0, "w": 0.5, "h": 1 } },
      "undocked": { "screen": "builtin",  "desktop": 1,
                    "layout": { "x": 0, "y": 0, "w": 1,   "h": 1 } },
      "groupID": "G-Drafts"
    }
  ],
  "profiles": [ { "id": "…", "name": "Default", "rules": [ … ],
                  "names": [ { "id": "N-Nova", "name": "Nova", "space": 1234 } ],
                  "plans": { "docked":   { "builtin": ["", "N-AI"],
                                           "external": ["N-Nova", "", ""] },
                             "undocked": { "builtin": ["", "N-AI", "N-Nova"] } },
                  "ghostDesktops": [ … ],
                  "pinGroups": [ { "id": "G-Drafts", "name": "Nova drafts" } ] } ],
  "pendingRemovals": { … }
}
```

- `rules` etkin profilin kural listesidir; `profiles` içinde o profilin
  kaydına da yazılır.
- `names` (id, ad, bağlı Alan ID’si ya da `null` = henüz masaüstü yok),
  `plans` (kurulum → ekran rolü → sıralı ad id’leri, `""` = adsız masaüstü;
  listenin uzunluğu masaüstü sayısıdır) ve `ghostDesktops` her profile aittir
  (şema 6). Bir adın planı, ekranı ya da numarası yoktur: Alan ID’sini izler.
  `nameID` taşıyan bir kural hedefi o adın masaüstünü hedefler; yanındaki
  `screen` ve `desktop` yalnızca son yerinin önbelleğidir. `pendingRemovals`
  en üst düzeyde kalır ve ortaktır. Şema 5 dosyaları (yuva başına
  `desktopNames`, `desktopNameSpaces`, `plannedDesktops`) bir kez,
  `Backups/pre-migration/` içine yedek alındıktan sonra yükseltilir.
- `tokens: []`, “uygulamanın bütün pencereleri” demektir.
- Okuma hoşgörülüdür: bozuk tek bir kural atlanır (dosya önce
  `rules.json.bak`’a kopyalanır ve alt çubuk kaç kuralın atlandığını gösterir).
- v1 dosyaları (`app` / `match` alanları) ve v2 dosyaları (profilsiz) okunurken
  taşınır; kuralları tek bir profil olur.
- `version` değeri 6’dan büyük olan bir dosyayı daha yeni bir Deskmap
  yazmıştır: okunur ama asla üzerine yazılmaz.
- Yukarıdaki anahtarlar kararlı bir biçimdir; yeni bir arayüz dili onları
  değiştirmez. Profil adları kullanıcı verisidir ve yazıldığı gibi saklanır.

Pin grupları: `profiles[].pinGroups` (`id`, `name`; dizi sırası çizim
sırasıdır) ve `rules[].groupID` (üyelik; bir pin en çok bir grupta). İkisi de
isteğe bağlıdır; eski sürümler yok sayar, dosyayı kaydederlerse düşürür; boş
liste ve `nil` yazılmaz. Etkin profilin gruplarının çalışma kopyası
(`Document.pinGroups`) üst düzeyde yazılmaz; çalışma kopyasıyla profil
arasında taşınan her alan `writeProfileFields` / `readProfileFields`’ten
geçer. Değişmez (K7): boş grup hiçbir örtük yolda budanmaz (yükleme,
`mutate`, Mission Control silmesi, `profile-set`, geri yükleme); yalnız açık
grup işlemleri `dropEmptyPinGroups()` ile biter, o da üyeleri `rules`’ta **ve**
`ghostDesktops[*].pins[*].rule`’da sayar; silinen masaüstünün grubu hayaletle
geri gelir. Okuyan taraf bilinmeyen `groupID`’yi grupsuz sayar. Router
`Rule.routingProjection`’ı (`groupID`’siz kurallar) karşılaştırır; grup
değişimi pencereleri yeniden yerleştirmez (K11).

### desktop-state.json {#desktop-statejson}

Bütün profillerin paylaştığı fiziksel bilgiler; yedeklere ve dışa aktarmalara
girmez (`desktop-spaces.json`’ın yerini alır; o dosya yükseltme için bir kez
okunur): `displays` (rol, ekran UUID’si, sıralı Alan ID’leri) ve `contents`
(Alan başına pencere ID’si, süreç ID’si, bundle ID; başlık yok), son kararlı
taramadaki hâliyle; `parked` (bir monitörden ayrılan adsız pencereler, geldikleri
masaüstüyle birlikte; pencere kapanınca ya da 14 gün sonra silinir);
`bootTime`; ve bir plan uygulanırken ayarlanan `transition`, böylece bir
çökmeden sonra bir sonraki açılışta kalınan yerden sürdürülebilir.
`DESKMAP_DATA_DIR` bütün veri klasörünü başka yere taşır.

### session-pins.json {#session-pinsjson}

Geçici sabitlemelerin listesi: `windowID`, `pid`, `bundleID`, `appName`,
`title`, `destination` (bir `nameID` taşıyabilir). Açılışta yalnızca pencere
ID’si pencere sunucusunda aynı süreç ID’siyle hâlâ var olan kayıtlar geri
getirilir.

### Profil dışa aktarma (`<name>.deskmap.json`) {#profile-export-namedeskmapjson}

```json
{ "kind": "deskmap-profile", "version": 5, "name": "Office",
  "exportedAt": "2026-09-14T10:00:00Z", "screens": [ … ], "rules": [ … ],
  "names": [ { "id": "N-Nova", "name": "Nova" } ],
  "plans": { "docked": { "external": ["N-Nova", "", ""] } } }
```

Sürüm 5 isteğe bağlı `pinGroups` ekler (içe aktarmada grup kimlikleri
yenilenir, kuralların `groupID`’leri eşlenir; bilinmeyen `groupID` düşer).
Sürüm 4 ve sürüm 3 dosyaları (`desktopNames`, `plannedDesktops`) hâlâ içe
aktarılabilir.
Adlar masaüstleri olmadan dışa aktarılır. İçe aktarırken kural ID’leri
yeniden üretilir, adlar masaüstü olmadan başlar (bir sonraki plan
uygulamasında plandaki sıralarına göre yerleşir), profil adı benzersiz yapılır
(`Office (2)`) ve `screens` içindeki bilinmeyen ekran rolleri haritaya
eklenir. `rules` dizisi olan düz, `rules.json` biçiminde bir dosya da kabul
edilir.

## URL şeması {#url-scheme}

`URLCommand.parse` saf bir fonksiyondur (birim testleri var): şema `deskmap`
olmalıdır; komut, büyük/küçük harf ayırt edilmeden ya ana makine kısmından
(`deskmap://reapply`) ya da ilk yol bileşeninden (`deskmap:reapply`) alınır.
`profile`, adı `name` sorgu öğesinden ya da yolun geri kalanından
(yüzde kodlaması çözülmüş olarak) alır. Pin grubu komutları (`group-add`,
`group-rename`, `group-remove`, `group-set`) `<grup>`’u
`Document.resolvePinGroup` ile çözer (önce kimlik, sonra büyük/küçük harf
duyarsız tam ad; aynı adlı birden çok grup hatadır). URL’ler
`NSApplicationDelegate.application(_:open:)` üzerinden gelir; bu, bir menü
çubuğu uygulamasında soğuk açılışta bile çalışır.

## Yerelleştirme {#localization}

- `Localization.swift`, `L(_ key: String)` ve
  `L(_ key: String, _ arguments: CVarArg...)` fonksiyonlarını tanımlar.
  Anahtar İngilizce metnin kendisidir. Arama `Bundle.main`’in `Localizable`
  tablosunda yapılır; tablo yoksa (testler, `swift run`) anahtarın kendisi,
  yani İngilizce metin döner.
- Türkçe metin `app/Resources/tr.lproj/Localizable.strings` içindedir;
  `app/Resources/en.lproj/Localizable.strings` bilerek boş bırakılmıştır,
  böylece paket İngilizceyi bildirir. `build-app.sh` her `*.lproj` klasörünü
  uygulamaya kopyalar; `Info.plist` de `CFBundleDevelopmentRegion = en` ve
  `CFBundleLocalizations = [en, tr]` bildirir.
- Anahtar kuralları (`LocalizationTests` denetler):
  - bir anahtar tek bir string literal’dir; `+` ve `\(...)` içermez;
  - değişken kısımlar biçim belirteçleri kullanır (`%@`, `%ld`); bunların
    sırasını değiştiren bir çeviri konumlu belirteçler kullanır (`%1$@`,
    `%2$ld`);
  - her anahtarın bir Türkçe karşılığı vardır, her Türkçe karşılık
    kullanılır, hiçbir anahtar iki kez geçmez ve anahtarla çevirinin
    belirteçleri aynıdır.
- Çoğullar kodda ele alınır (`n == 1 ? L("1 pin") : L("%ld pins", n)`).
- Bilerek yerelleştirilmeyenler: macOS ayarları kartındaki ayar adları
  (Sistem Ayarları’nın İngilizcede gösterdiğiyle aynı olmalı), günlük
  iletileri ve veri anahtarları.

Yeni bir dil eklemek için `app/Resources/<code>.lproj/Localizable.strings`
dosyasını oluştur, kodu `scripts/build-app.sh` içindeki
`CFBundleLocalizations`’a ekle ve `LocalizationTests`’i yeni tabloyu
denetleyecek şekilde genişlet.

## Günlük kaydı {#logging}

`Log` (`Services/Log.swift`), `com.deskmap.app` alt sistemi altında dört
`os.Logger` kategorisi tanımlar: `routing` (taşımalar, vazgeçmeler, geçici
sabitlemelerin süresinin dolması), `skylight` (kullanılabilirlik ve taşıma
yolu), `ax` (yanıt vermeyen uygulamalar, gözlemci kaydı), `screens` (ekran
değişiklikleri, uyku/uyanma). Tarama başına hiçbir şey günlüğe yazılmaz.
Pencere başlıkları `.private` olarak yazılır.

## Testler {#tests}

`app/Tests/DeskmapTests` (Swift Testing):

| Grup | Kapsadığı |
|---|---|
| `RuleTests` | Eşleştirme (bundle ID ve ad; Türkçe İ/ı ve ß dahil Unicode büyük/küçük harf kuralları), özgüllük sırası, başlığı parçalara ayırma, `sameKey`, plan başına hedefler |
| `LayoutTests` | `WindowLayout` kesirleri, sınırlama, etiketler, Cocoa → AX koordinat dönüşümü, çerçeve toleransı |
| `DocumentCodableTests` | `rules.json` v1/v2/v3 çözümleme, hedef varsayılanları, atlanan bozuk kurallar, daha yeni sürümü algılama |
| `DocumentOperationsTests` | Masaüstü eşlemesi ve tersi, masaüstlerini yeniden sıralama, sabitleme/sabitlemeyi kaldırma, profiller, içe/dışa aktarma |
| `RoutingTests` | `Routing.select` ve düzen denemelerinin sayımı |
| `RouterSelectionTests`, `WindowDriftBugTests`, `WindowDriftFixTests` | Gerçek Router'ın tarama seçimi ve birleştirmesi, sahte ekran ve pencerelerle (`RouterHarness`, `Router.sweepSelection`): yapışkan bağlar, genel başlık beklemesi, tam başlık sahipleri, pin kaldırma, duraklatılmış/yatışan yönlendirme; Router'ın bağıyla grup taşıma ve gölge listesi |
| `EngineHelperTests` | Geri çekilme kararı, AX zaman aşımları, pencere sunucusu süzgeçleri, taşıma denemeleri ve bekleme süresi, canlı pencere birleştirme, duraklatma güvenliği, yatışma üst sınırı, harici ekran sırası, Alan türleri, `Router.placement` |
| `ChangeHistoryTests` | Çok adımlı geri al/yinele, atılan yineleme dalı ve onun geri alınması, bir satıra dönme, 50 kayıt sınırı, gürültü ile izlenmeyen değişiklikler, eşlik eden kayıtlar |
| `MapLogicTests` | Gölgede kalan sabitlemeler, eksik masaüstü rozeti |
| `TokenEditingTests` | `Document.setTokens` (kimlik, anahtar çakışmaları) ve başlık parçası seçici yardımcıları |
| `PinGroupCodableTests`, `PinGroupModelTests`, `PinGroupStoreTests` | Pin grubu alanları (eski dosyalar bayt düzeyinde aynı, hoşgörülü okuma), belge işlemleri (K7, hayaletler, profil kapsamı, kopya/içe aktarma), işlem başına tek geri alma adımı |
| `PinGroupLayoutTests`, `RouterProjectionTests`, `PinGroupURLTests` | Haritadaki grup kutuları, Router'ın gruba kör kural anahtarı, URL komutları ve `status.json` |
| `LocalizationTests` | Anahtar/çeviri tutarlılığı (yukarıya bak) |

Testler hiçbir zaman bir `Store` ya da `Router` oluşturmaz; bu yüzden
`rules.json`’a ya da gerçek pencerelere hiç dokunmazlar.
