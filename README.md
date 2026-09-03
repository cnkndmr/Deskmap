# Space Router

Pencere başlığında görünen **workspace adına** göre pencereleri doğru
monitöre, doğru macOS masaüstüne (Space) ve doğru düzene yerleştiren
menü çubuğu uygulaması. Tek bir `.app`; Hammerspoon veya başka bir
yardımcı program gerekmez.

Uygulamadan bağımsızdır: Safari Tab Group, VS Code workspace, Obsidian
vault, iTerm profili — başlıkta ad gösteren her pencere.

## Nasıl kullanılır

1. Menü çubuğundaki simgeye tıklayın, **+** ile açık bir pencere seçin.
2. Başlığın hangi parçasının bu pencereyi tanımladığını işaretleyin
   (ör. dosya adı değil, proje adı).
3. Oluşan çipi haritada istediğiniz ekranın istediğiniz masaüstüne
   **sürükleyin**. Çipe tıklayıp düzeni (sol yarı, tam, orta…) seçin.
4. Üstteki laptop / monitör düğmesiyle diğer duruma geçip aynı şeyi
   orası için yapın. Monitör takıldığında veya çıkarıldığında pencereler
   otomatik yeniden yerleşir.

Bir çipi alttaki tepsiye bırakmak o durumda pencereyi serbest bırakır.

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
**Girişte başlat**.

## Nasıl çalışır

```
app/Sources/SpaceRouter/
├── Models/     Rule, Destination, WindowLayout ve rules.json deposu
├── Services/
│   ├── Accessibility.swift   Pencere listesi, başlık, çerçeve (AX API)
│   ├── SkyLight.swift        Space okuma/taşıma (özel SkyLight çağrıları)
│   ├── ScreenService.swift   Bağlı ekranlar, dock durumu
│   └── Router.swift          2 sn'de bir tarama, taşıma ve düzen
└── Views/      Ekran haritası, sürüklenebilir çipler, pencere seçici
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
make clean
```
