# Space Router

Pencere başlığında görünen **workspace adına** göre pencereleri doğru
monitöre, doğru macOS masaüstüne (Space) ve doğru düzene yerleştiren
menü çubuğu uygulaması. Tek bir `.app`; Hammerspoon veya başka bir
yardımcı program gerekmez.

Uygulamadan bağımsızdır: Safari Tab Group, VS Code workspace, Obsidian
vault, iTerm profili — başlıkta ad gösteren her pencere.

## Nasıl kullanılır

1. Menü çubuğundaki simgeye tıklayın. Harita, ekranları ve masaüstlerini
   açık pencerelerle gösterir. Bir pencere satırındaki **pin** düğmesine
   basın.
2. Başlığın hangi parçasının bu pencereyi tanımladığını işaretleyin
   (ör. dosya adı değil, proje adı). "Tüm pencereler" uygulamanın her
   penceresini pinler; "Sadece bu pencere" başlığa bakmadan yalnızca o
   pencereyi, bu oturum için tutar.
3. Pinli satırı ya da çipi haritada başka ekranın başka masaüstüne
   **sürükleyin**; tıklayıp düzeni (sol yarı, tam, orta…) seçin. Pinsiz bir
   satırı sürüklemek pencereyi bir kez taşır, pin yazmaz.
4. Üstteki laptop / monitör düğmesiyle (⌘1 / ⌘2) diğer duruma geçip aynı
   şeyi orası için yapın; iki kurulum birbirinden bağımsızdır. Monitör
   takıldığında veya çıkarıldığında pencereler otomatik yeniden yerleşir.

Bir çipi alttaki tepsiye bırakmak o durumda pencereyi serbest bırakır.

**Parçaları sonradan değiştirmek:** pinli satıra ya da çipe tıklayın; pine
uyan bir pencere açıksa panelde başlığın parçaları yeniden seçilir ve
**Uygula** ile yazılır. Başka bir pinle aynı uygulama + aynı parçalara
düşen seçim uygulanmaz, panel nedenini söyler.

**Geri alma:** pin kaldırma, profil silme, masaüstü sırası değiştirme,
sürükleyerek taşıma (geçici pinler dahil), var olan pinin hedefini yeniden
pinleyerek ezme ve parça düzenleme sonrasında alt çubukta 10 sn
"… · Geri al" görünür; tıklayın ya da ⌘Z basın. Tek seviyedir; onay
diyaloğu yerine bunu kullanın. Araya başka bir değişiklik girerse (yeni pin,
düzen adımı, profil geçişi) kayıt düşer; geri alma yalnızca o işlemi geri
alır. Geçici pin ekleme ve kaldırma geri alınamaz. Odak bir metin
alanındayken ⌘Z o metnin geri almasıdır.

**Kısayollar** (pencere öndeyken): ⌘R pinli pencereleri şimdi yerleştir,
⌘1 / ⌘2 mod seçici, ⌘Z geri al, Esc açık paneli kapat.

Bir pinin hedef masaüstü o ekranda yoksa (Mission Control'de o kadar
masaüstü açık değilse) pencere son masaüstüne gider ve satırda turuncu
"M5→3" rozeti çıkar (yalnızca şu anki modun haritasında); masaüstü ekleyin
ya da pini sürükleyin. Bir pencereye
uyan ama daha özgül bir pine yenilen pin haritada soluk çip olarak durur.

## Kurulum

```
xcode-select --install     # bir kez
make run                   # derler, build/SpaceRouter.app'i açar
```

İlk açılışta **Erişilebilirlik** izni ister (System Settings › Privacy &
Security › Accessibility). İzin verildikten sonra uygulamayı yeniden
başlatmak gerekebilir.

### Gerekli macOS ayarları (bunlar yapılmazsa uygulama düzgün çalışmaz)

Uygulama açılınca bu ayarları kendisi denetler ve yanlış olanı turuncu
kartla gösterir; kart ayar düzelene kadar kapanmaz.

**System Settings › Desktop & Dock › Mission Control** bölümü:

| Ayar | Olması gereken | Neden |
|---|---|---|
| Automatically rearrange Spaces based on most recent use | **Kapalı** | Açıkken macOS masaüstü sırasını değiştirir: Dock'tan başka masaüstündeki uygulamaya geçiş komşu Space'e gider, pencere belirip kaybolur, pinlerin masaüstü numaraları kayar. |
| When switching to an application, switch to a Space with open windows | **Açık** | Kapalıyken Dock'a tıklamak masaüstü değiştirmez. |
| Group windows by application | Kapalı (önerilir) | Mission Control sırası ile masaüstü numaraları uyuşmayabilir. |
| Displays have separate Spaces | **Açık** | Kapalıyken harici ekranın masaüstleri görülemez. |

**Dock simgesi › sağ tık › Options › Assign To → None.** Pinlediğin
uygulamalarda "This Desktop" / "All Desktops" seçili olmamalı; macOS
pencereyi kendi atadığı Space'e çeker ve Space Router'ın taşımasıyla
çelişir.

Bu liste 3 Eylül 2026'da yaşanan bir sorundan çıktı: "Automatically
rearrange Spaces" açıkken Dock'tan uygulamaya geçiş önce komşu Space'e
gidiyor, uygulama kısa süre görünüp kayboluyordu; ayar kapatılınca düzeldi.

Kalıcı kurulum: `cp -R build/SpaceRouter.app /Applications/` ve menüden
**Girişte başlat**. Uygulama /Applications dışından çalışıyorsa (ör.
`build/` içinden) "Girişte başlat" o kopyayı kaydeder; onay kutusunun
ipucu yolu gösterir. macOS onay bekliyorsa yanında **Onay gerekli**
bağlantısı çıkar, tıklayınca Login Items ayarı açılır.

Aynı anda ikinci bir Space Router açılırsa (ör. `build/` ve
`/Applications` kopyaları) yenisi hiçbir şey yapmadan kapanır; iki
yönlendirici aynı pencereleri çekiştirmesin.

## Otomasyon

Uygulama `spacerouter://` URL şemasını tanır. Shortcuts, Raycast,
Hammerspoon, Keyboard Maestro ya da terminal, bir URL açarak komut verir;
uygulama kapalıysa macOS önce onu başlatır.

| URL | Etkisi |
|---|---|
| `spacerouter://reapply` | Pinli pencereleri şimdi yerleştir (menüdeki ↻ ile aynı) |
| `spacerouter://pause` | Yönlendirmeyi duraklat |
| `spacerouter://resume` | Yönlendirmeyi sürdür |
| `spacerouter://toggle` | Duraklat / sürdür |
| `spacerouter://profile/<ad>` | Adı verilen profile geç (büyük/küçük harf önemsiz) |
| `spacerouter://profile?name=<ad>` | Aynı; adında `/` olan profiller için |
| `spacerouter://next-profile` | Sıradaki profile geç, sondan başa döner |

Boşluk ve Türkçe karakterler yüzde kodlanır: `Ofis Masası` →
`spacerouter://profile/Ofis%20Masas%C4%B1`. Bilinmeyen komut ya da
profil, uygulamanın alt çubuğunda kırmızı bir hata olarak görünür; başka
bildirim yoktur.

Terminal:

```
open "spacerouter://profile/Ofis"
open "spacerouter://reapply"
```

Shortcuts: **Open URLs** (URL'leri Aç) eylemine `spacerouter://profile/Ev`
yazın; kısayola klavye kısayolu ya da Focus otomasyonu bağlayın.

Hammerspoon:

```lua
hs.hotkey.bind({"cmd", "alt"}, "1", function()
  hs.urlevent.openURL("spacerouter://profile/Ofis")
end)
```

Raycast: **Quicklinks** ile `spacerouter://toggle` gibi bir bağlantı
oluşturun.

## Nasıl çalışır

```
app/Sources/SpaceRouter/
├── Models/     Rule, Destination, WindowLayout ve rules.json deposu
├── Services/
│   ├── Accessibility.swift   Pencere listesi, başlık, çerçeve (AX API)
│   ├── SkyLight.swift        Space okuma/taşıma (özel SkyLight çağrıları)
│   ├── ScreenService.swift   Bağlı ekranlar, dock durumu
│   ├── URLCommands.swift     spacerouter:// komutları (ayrıştırma + çalıştırma)
│   └── Router.swift          2 sn'de bir tarama, taşıma ve düzen
└── Views/      Ekran haritası, sürüklenebilir çipler, pin ve profil panelleri
```

macOS'ta bir pencereyi başka bir Space'e taşımanın resmî bir API'si yok.
`SkyLight.swift`, Hammerspoon ve yabai'nin kullandığı özel çağrıları
(`SLSMoveWindowsToManagedSpace`, `SLSSpaceSetCompatID` +
`SLSSetWindowListWorkspace`, macOS 26.4+ için
`SLSBridgedMoveWindowsToManagedSpaceOperation`) `dlsym` ile çalışma
anında çözer; sürüme göre uygun olanı seçer. Bir simge bulunamazsa
uygulama çökmez, yalnızca Space taşıma atlanır ve pencere yine ekran ve
düzene oturtulur.

Kurallar `~/Library/Application Support/SpaceRouter/rules.json`
dosyasında tutulur; eski (v1) dosyalar otomatik okunur.

## Geliştirme

```
make app      # release derleme + .app paketi
make check    # debug derleme
make test     # birim testleri (app/Tests/SpaceRouterTests, Swift Testing)
make dist     # gönderilebilir paket: evrensel derleme + imza + build/dist/*.zip
make clean
make concurrency-check  # sıkı eşzamanlılık uyarıları (Swift 6 hazırlığı; ayar değişmez)
```

Testler saf mantığı kapsar: `Rule` eşleştirme ve başlık parçalama,
`WindowLayout` oranları, `rules.json` şema geçişleri, `Document` üzerindeki
pin/profil/parça işlemleri, `Routing` hedef seçimi, `UndoBuffer` (geçerlilik
denetimi dahil), masaüstü taşıma haritasının tersi, gölgede kalan kural
hesabı ve eksik masaüstü rozeti kararı. Diske ya da pencerelere
dokunmazlar. `git config core.hooksPath .githooks` ile commit öncesi derleme ve
testler kendiliğinden çalışır. Sürüm numarası kökteki `VERSION` dosyasından okunur.

### Dağıtım

`make dist` arm64 + x86_64 evrensel bir `SpaceRouter.app` üretir ve
`build/dist/SpaceRouter-<sürüm>.zip` olarak paketler (`FORMAT=dmg` ya da
`FORMAT=both` ile DMG; `VERSION=0.3.1` ile sürüm). Varsayılan imza ad-hoc'tur:
alıcı uygulamayı ilk kez **sağ tık › Open** ile açmalı ya da
`xattr -dr com.apple.quarantine /Applications/SpaceRouter.app` çalıştırmalıdır.
Developer ID hesabıyla Gatekeeper'sız dağıtım için:

```
xcrun notarytool store-credentials notary --apple-id ... --team-id ... --password <app-specific>
SIGN_IDENTITY="Developer ID Application: Ad (TEAMID)" NOTARY_PROFILE=notary make dist
```

### Günlük

Motor `os.Logger` ile seyrek günlük yazar (alt sistem `com.spacerouter.app`;
kategoriler `routing`, `skylight`, `ax`, `screens`): açılışta SkyLight
durumu ve masaüstü taşıma yolu, her masaüstü taşıması, vazgeçmeler, yanıt
vermeyen uygulama backoff'u, ekran yatışması, uyku/uyanma ve oturum pini
düşmesi. Pencere başlıkları gizlidir. Terminalden izlemek için:

```
log stream --predicate 'subsystem == "com.spacerouter.app"' --level info
```
