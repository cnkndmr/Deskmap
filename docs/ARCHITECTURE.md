# Mimari ve tasarım kararları

## Genel akış

```
┌──────────────────────────────┐
│ SwiftUI menü çubuğu uygulaması│  kural düzenleme, ekran kaydı,
│                              │  izin durumu, canlı başlık testi
└───────────────┬──────────────┘
                │ atomik JSON yazma
                ▼
  ~/Library/Application Support/SpaceRouter/rules.json
                │ hs.pathwatcher
                ▼
┌──────────────────────────────┐
│ Hammerspoon motoru (Lua)     │
│                              │
│  config  → doğrulama         │
│  apps    → uygulama eşleşmesi│
│  router  → kural + hedef     │
│  screens → UUID, dock durumu │
│  layout  → oran → piksel     │
│  spaces  → Desktop taşıma    │
└──────────────────────────────┘
```

## Neden iki katman?

Bir pencereyi belirli bir macOS Space'e taşımanın **resmî public API'si
yok**. Eski `kCGWindowWorkspace` özelliği kullanımdan kaldırıldı.

Üç seçenek vardı:

| Yaklaşım | Güç | Kırılganlık | App Store |
|---|---|---|---|
| Yalnızca Focus + Shortcuts | düşük | düşük | uygun |
| SwiftUI + Hammerspoon | yüksek | orta | uygun değil |
| Tamamen private API | yüksek | yüksek | uygun değil |

İkincisi seçildi. Space taşıma riski, bu işi zaten yapan ve macOS
sürümlerine göre güncellenen Hammerspoon'un `hs.spaces` modülüne
devredildi. Uygulama tarafında yalnızca public API kullanılır:
`NSScreen`, `CGDisplayCreateUUIDFromDisplayID`, Accessibility API,
`MenuBarExtra`.

Sonuç: Hammerspoon bir macOS güncellemesinde bozulursa uygulamanın
kendisi değil, yalnızca taşıma katmanı etkilenir; kurallar ve UI durur.

## Neden pencere başlığı?

Safari, Tab Group'ları AppleScript sözlüğünde nesne olarak açmıyor.
VS Code da workspace'i dışarıya vermiyor. Buna karşılık her ikisi de
adı **pencere başlığında** gösteriyor ve Accessibility API başlığı
okumaya ve başlık değişimini dinlemeye izin veriyor
(`kAXTitleChangedNotification`).

Bu yüzden motor uygulamaya özel hiçbir varsayım yapmaz: kural
`app + başlık deseni` çiftidir. Başlıkta ayırt edici bir metin
gösterebilen her uygulama desteklenir.

## Tasarım kararları

**UUID ile ekran kimliği.** Ekran adları ve sıraları değişir; UUID
değişmez. Dock tespiti "harici rolü verilmiş bir UUID bağlı mı"
sorusudur.

**Oransal layout.** Piksel yerine 0..1 oranları saklanır. Aynı kural
farklı çözünürlük ve ölçeklemelerde çalışır.

**Normal Desktop sayımı.** `desktop: 2`, o ekrandaki ikinci *normal*
masaüstüdür. Tam ekran ve Split View Space'leri sayıma katılmaz; aksi
hâlde bir uygulamayı tam ekran yapmak tüm kuralları kaydırırdı.

**İki ayrı yeniden yükleme.** `rules.json` değişince yalnızca kurallar
tazelenir — ucuzdur ve saniyede birkaç kez olabilir. Motorun Lua kodu
değişince Hammerspoon'un tamamı yeniden yüklenir, çünkü Lua modülleri
`package.loaded` içinde önbelleklenir. Motor kendi kaynak dizinini
izleyerek bunu kendisi tetikler.

**Masaüstü sabitleme. Sıra numarası ("bu ekranın 2. masaüstü")
kırılgandır: aynı ekrana masaüstü eklenince hedef kayar. Sıra bir kez
çözülür ve gerçek Space kimliği `pins.json` dosyasına yazılır; sonraki
yerleştirmelerde bu kimlik kullanılır. Sabitleme motora aittir, çünkü
`rules.json` uygulamaya aittir ve iki taraf aynı dosyayı yazarsa
birbirini ezer.

**Debounce. Başlık değişimi yazarken karakter karakter tetiklenebilir.
Pencere başına zamanlayıcı, art arda gelen olayları tek işleme indirir.

**Geri besleme kilidi.** `setFrame` çağrısı `windowMoved` olayını
tetikler. Yönlendirme sırasında pencere kimliği kilitlenir; aksi hâlde
motor kendi hareketine tepki verip döngüye girer.

**Atomik yazma.** Uygulama `rules.json` dosyasını geçici dosya üzerinden
yazar; motor yarım yazılmış JSON okumaz.

**Tolerant doğrulama.** Geçersiz bir kural tüm yapılandırmayı düşürmez;
o kural atlanır ve konsola sebebi yazılır.

## Bilinen sınırlar

- `hs.spaces` private API kullanır ve "experimental" olarak işaretlidir.
  macOS büyük sürüm güncellemelerinden sonra Hammerspoon güncellemesi
  gerekebilir.
- Tam ekran pencereler taşınmaz; macOS onları ayrı bir Space türünde
  tutar.
- Bağlı olmayan bir monitörün görünmez Space'inde kalan pencere, siz o
  pencereye odaklanana kadar bulunamayabilir. `windowFocused` olayı
  yönlendirmeyi yeniden çalıştırır.
- Aynı adı taşıyan iki workspace ayırt edilemez; başlık metni benzersiz
  olmalıdır.
- Mac App Store dağıtımı bu mimaride mümkün değildir.

## Sonraki adımlar

- Space taşıma katmanını bağımsız bir yardımcı sürece taşımak
  (Hammerspoon bağımlılığını kaldırmak)
- Kural içe/dışa aktarma
- Focus modu entegrasyonu
- Kural başına birden fazla pencere için otomatik döşeme
