# Deskmap 0.6.0 — sürüm notları

26 Ekim 2026'da yayımlandı. [CHANGELOG](CHANGELOG.md) dosyasının 0.6.0
bölümünden yazıldı. İngilizcesi: [../release-0.6.0.md](../release-0.6.0.md).

0.5.0 (30 Eylül 2026) indirilebilen ilk sürümdü. 0.6.0 o günden beri biriken
her şeyi topluyor: masaüstünü izleyen adlar, kendi rolü olan ikinci harici
monitör, pin grupları, kendi düzenlerin, çok adımlı geri alma, otomatik yedekler,
betiklenebilir bir CLI ve bir web sitesi. Yeni bir izin gerekmez; verdiğin Erişilebilirlik izni, uygulama
aynı biçimde imzalandığı sürece geçerli kalır (bkz. *Yükseltme*).

## Öne çıkanlar

- **İkinci harici monitör kendi düzenini korur.** Her monitör durduğu yerle
  değil ekran UUID'siyle tanınır; kabloları ya da ekran dizilimini değiştirmek
  sabitlemeleri artık öteki monitöre kaydırmaz.
- **Masaüstü adı numaraya değil masaüstüne aittir.** Ad, ekranlar arasında,
  sıralama değişince ve monitör takılıp çıkarılınca masaüstünü izler;
  sabitleme bir adı hedef alabilir.
- **Pin grupları**: pinleri bir ad altında topla, tek parça taşı, aç, kapat.
- **Kendi düzenlerin**: Ayarlar › Düzenler'de ızgarada çiz, adlandır.
- **İstediğin kadar adım geri al** (⌘Z / ⇧⌘Z), değişiklik geçmişiyle.
- **Otomatik yedekler**: profiller, sabitlemeler, adlar; Ayarlar'dan geri
  yükleme.
- **`deskmap` komut satırı aracı**, `status.json` ve `deskmap://` komutları;
  betikler ve ajanlar için.
- **Bütün çalışma alanını tek tıkla aç ya da kapat**, haritadan.
- **macOS 15 ve 26.0–26.3'te masaüstü taşıma kapalı başlar**; orada henüz
  doğrulanmadığı için **Yine de dene** diyene kadar açılmaz.

## Yenilikler

### Ekranlar ve monitörler

- **UUID'ye göre monitör rolleri.** Her harici monitör rolünü (*Ekstra
  monitör*, *2. monitör*, …) soldan sağa konumuyla değil ekran UUID'siyle
  korur. Ekranların yerini değiştirmek, başka sırayla takmak, sola eklenen
  sanal ekran ya da aynı model iki monitör sabitlemeleri artık öteki monitöre
  kaydırmaz. İki ya da daha çok monitörde ikinci kartın başlığı onları yer
  değiştiren bir menüdür (önce sorar). `deskmap screen-role` ile `screen-role`
  / `screen-role-forget` URL komutları aynısını yapar.
- **Deskmap'in hatırlamadığı monitör bekler.** İlk monitör öğrenildikten
  sonra rolünde hatırlanmayan ekran (yeni monitör, tek kalan sanal ekran,
  unutulan monitör) beklemededir: ona plan, sabitleme ya da kural uygulanmaz,
  orada temizlik yapılmaz. Kartında *yeni monitör · düzen bekliyor* yazar;
  menüde *Ekstra monitör / 2. monitör … olarak kullan* (onaylı), hatırlananlarda
  *Bu monitörü unut* vardır.
- **Birden çok monitörde sıralı yerler**: sabitlenmiş pencereyi başka bir
  monitöre bırakınca eski yeri yenisinin altında saklanır; monitörü bağlı ilk
  yer kazanır, böylece 2. monitör çıkınca pencereleri geri döner. Hiçbiri bağlı
  değilse pencereyi rol sırasında bağlı ilk monitör alır. Düzen dosyaları
  `docked: [external-2/1, external/2]` kabul eder.
- **Masaüstünü başka ekrana gönder**, bağlam menüsünden; haritada masaüstleri
  ekranlar arasında sürüklenir.

### Masaüstü adları ve planlar

- **Adlar v2.** Bir ad tek bir fiziksel masaüstüne aittir; ekranlar arasında,
  sıralama değişince, monitör takılıp çıkarılınca onu izler. Her profilin her
  kurulum için bir planı vardır (hangi ad nerede, her ekranda kaç masaüstü).
  Monitör takılıp çıkarılınca yeni kurulumun planı uygulanır: adlı masaüstleri
  bütün pencereleriyle taşınır, monitör masaüstündeki adsız pencereler laptop
  masaüstlerine park edilir ve monitör dönünce geri gelir, eksik masaüstleri
  oluşturulur, yalnız planın dışında kalan *boş* masaüstleri silinir (her biri
  silinmeden hemen önce yeniden denetlenir).
- **Adlar profile aittir.** Yeni profil adsız başlar; bir profilde yeniden
  adlandırmak ötekine dokunmaz; dışa / içe aktarma adları ve planları taşır.
- **Sabitleme bir adı hedef alabilir.** Sabitleme paneli ve **Gönder** önce
  adları listeler. Sabitleme adlı masaüstünü izler, adın masaüstü yokken
  bekler (hiçbir şey taşınmaz). `deskmap://pin/<window>?name=<name>` aynısını
  yapar.
- **Sadece laptop planını buraya kopyala** (⋯ menüsü) laptop masaüstlerinin
  adlarını da Monitör bağlı planına kopyalar.
- **İçinde pencere olan masaüstünü silmek önce sorar.** Profil değiştirmek ve
  kopyalama pencereleri taşır ama masaüstü silmez.
- **Mission Control'de silinen masaüstleri** sabitlemeleriyle birlikte geri
  getirilebilir satır olarak kalır; Deskmap kapalıyken silinenler de.

### Harita ve günlük kullanım

- **Çalışma alanını tek seferde aç.** Kapalı sabit pencereleri olan
  masaüstünün adının yanında **N aç** görünür; tek tık hepsini kendi yerine
  açar. Her uygulama grubunun başlığında **↗** (kapalı sabitleri aç) ve **✕**
  (grubun bütün sabit pencerelerini kendi kapatma düğmesiyle kapat; uygulama
  çalışır kalır, kaydedilmemiş belgeler yine sorar).
- **Masaüstü kartlarından oluşan görsel harita**, yanında düz bir kural
  cümlesiyle denetçi, temel/ileri düzenleyici, **Neden burada?** kutusu, lejant
  ve etiketli üst çubuk. Menü çubuğunda **durum noktası** (yeşil/turuncu/
  kırmızı) ve haritanın üstünde tek satırlık gerekçe.
- **Daha basit sabitleme**: *bu pencere* (kararlı başlık anahtarı: dosya yolu,
  kararlı başlık parçası ya da Safari sekme grubu) ya da *uygulamanın bütün
  pencereleri*. ⌘-tıkla çok pencere seçip tek adımda oldukları yere sabitle.
  Bütün uygulama grubunu sürükleyerek ya da bağlam menüsünden başka masaüstüne
  taşı.
- **Çift tık**: pencere satırına çift tık pencereye odaklanır ve masaüstüne
  geçer; kapalı sabitlemeye çift tık penceresini (dosya, klasör ya da sayfa)
  yeniden açar.
- **Zamanlı pinler kutusu** kenar çubuğunun altında: bir süre serbest bırakılan
  pencereler, süresi en önce biten başta, **Hepsini bitir** düğmesiyle. Serbest
  harekete 2 sa, 5 sa ve *ekran kilitlenene kadar* süreleri, `deskmap://free`
  ve `deskmap free` eklendi.
- **Harita penceresinin yerleşimi**: her açılışta bir kez, ekrana sığan sabit
  yükseklikte, dahili ekranın üst ortasında; yeniden boyutlandırmadan sonra
  artık oradan oraya itilmez.

### Pin grupları ve düzenler

- **Pin grupları.** Pencerelere ve pin çiplerine ⌘ ile tıkla › **Grup olarak
  pinle**, ya da sağ tık › **Gruba ekle**. Grup tek parça taşınır (başlığını
  sürükle ya da **Grubu gönder**), tek düğmeyle açılıp kapanır, yeniden
  adlandırılabilir. Ayrıca `deskmap group …` ve `deskmap://group-*`. **Eski bir
  Deskmap `rules.json`'u kaydederse gruplar düşer** (pinler kalır).
- **Kendi düzenlerin.** Ayarlar › Düzenler Temel, Gelişmiş ve Gizli düzenleri
  listeler; ızgarada ya da kenar boşluklarıyla yenisini çiz, adlandır, sırala,
  normal ya da ultra geniş ekranla sınırla, **Varsayılanlara dön…**. Bir düzeni
  değiştirmek hiçbir pencereyi taşımaz.
- **Öteki planın düzenini kullan.** Bir pinin iki planı pencereyi aynı yere
  farklı düzenle koyuyorsa paneli öteki düzeni önerir (`deskmap rule
  copy-layout`).
- **Mission Control'de başka ekrana sürüklenen masaüstü geri taşınır** (ya da
  sorar, ya da kalır: Ayarlar › Genel); bir kart **Orada kalsın** seçeneği sunar.

### Hız

- **İsteğe bağlı performans anahtarları** (`defaults` içinde `perf.*`, hepsi
  varsayılan kapalı): tarama değişmeyen pencereleri atlar, uygulamalar paralel
  okunur, ekran değişimi oturana kadar yoklanır, tek bir yavaş uygulama tarama
  kuyruğunu tıkamaz. Test düzeneğinde hepsi açıkken takılan tarama 2,7 sn'den
  0,03 sn'ye, tak/çıkar zinciri 4,4 sn'den 0,35 sn'ye indi. `status.json`
  bunları `perfFlags` olarak listeler.
- **Chrome pencereleri 0,8 sn yerine yaklaşık 40 ms'de taşınır** (gelişmiş
  erişilebilirlik kipi taşıma sırasında kapatılır).

### Geri alma ve geçmiş

- **Çok adımlı geri al / yinele.** Bu oturumdaki her ayar değişikliği bir
  adımdır (en çok 50, kaydedilmez): ⌘Z / ⇧⌘Z ve alt çubukta hep duran ↶ ↷
  düğmeleri 10 saniyelik *· Geri al* bağlantısının yerini alır. **Son
  hareketler**'de iki sekme: **Değişiklikler** (en yenisi başta, ● ŞİMDİ,
  **Buraya dön**) ve **Pencere hareketleri**. URL komutları, CLI, profil
  değiştirme ya da Mission Control'den gelen değişiklikler geri almayı iptal
  etmek yerine adım olur.

### Yedekler

- **Otomatik yedekler**: bütün profiller, sabitlemeler ve masaüstü adları
  saatlik (24 saat tutulur), günlük (7 gün), haftalık (süresiz) olarak
  `~/Library/Application Support/Deskmap/Backups/` altında. Geri yükleme
  **Ayarlar › Yedekler** (ya da profil panelinde **Yedekler…**) ya da
  `deskmap backups` / `deskmap backup-restore <id>`; önce o anki durum
  yedeklenir, geri yükleme geri alınabilir. Harici `profile-backup.sh`
  betiğinin yerini alır.

### Doğrulanmamış macOS sürümlerinde masaüstü taşıma

- Pencereleri masaüstleri arasında taşımanın doğrulanmadığı macOS 15.x ve
  26.0–26.3'te masaüstü taşıma **kapalı başlar**; ana pencerede bunu söyleyen
  bir kart görünür. Ekran ve düzen yine uygulanır. **Yine de dene** taşımayı
  açar ve hatırlanır; devre kesici her taşımayı izlemeye devam eder. Taşımalar
  etkisiz kalırsa **Yeniden dene** yeniden açar. `status.json` `desktopMoves`
  yazar; taşıma kapalıysa `deskmap status` bir satırla söyler.

### Komut satırı, otomasyon, kancalar

- **`deskmap` CLI** (`scripts/deskmap`): `status`, `screens`, `desktops`,
  `rules`, düzen dosyalarıyla `apply` / `check` / `undo`, `dump`, profil
  yeniden adlandırma/dışa aktarma, masaüstü sıralama, `save-layout`, `free`,
  `screen-role`, `backups`, `backup-restore`, `hooks`.
  `deskmap --help` ajanlar için yerleştirme rehberi taşır. `make cli-test`
  çevrimdışı birim testlerini koşar.
- **`status.json`** (adlar, planlar, `uuid`'li ekranlar, `heldRoles`,
  `desktopMoves`, serbest hareket durumu) ve **URL komutları**
  (`deskmap://pin`, `profile-set`, `plan-desktops`, `free`, `screen-role`,
  `quit`, …). `DESKMAP_DATA_DIR` uygulamayı başka veri
  klasörüne yönlendirir.
- **Ekran değişim kancaları** (`hooks.json`): ekran takılınca, çıkarılınca ya
  da değişince komut çalıştırır; fare bırakılmasını bekler, komutlara zaman
  sınırı koyar.

### Belgeler ve web sitesi

- **Web sitesi** (`website/`, `make site`): ana sayfa, indirme, karşılaştırma
  ve belge sayfaları İngilizce ve Türkçe; kılavuz, başvuru, mimari, gizlilik ve
  değişiklik günlüğü Markdown belgelerden derlenip
  `.github/workflows/pages.yml` ile GitHub Pages'e yayımlanır. Tek sayfalık
  `docs/site/` kalktı.
- **Demo GIF** (`docs/media/<dil>/demo.gif`) README ve kılavuzda:
  sadece laptop, monitör bağlandı, sabit pencereler yerinde, kendi rolüyle
  ikinci monitör. Ekran görüntüsü kipi demo veriyle çizer; gerçek pencereye
  dokunulmaz.
- **Homebrew tap**: `brew install --cask cnkndmr/tap/deskmap`; cask, sürüm
  yayımlanınca kendiliğinden güncellenir.
- **Hata tabloları** (`docs/tr/bug-tables.md`): birincil harici monitör ve
  pencere kayması için işlem × durum tabloları; her hücre bir test.

## Düzeltilenler

- **Pencereler başlığı değişince başka sabitlemeye kaymıyor.** Pencere, onu
  yerleştiren kuralda ömrü boyunca kalır (yapışkan bağ); genel başlık
  (uygulama adına eşit) bir bekleme süresi alır; başlığı tek sözcüklük bir
  kurala tam eşit bir pencere açıkken o sözcüğü yalnız içeren pencereler o
  kurala uymaz; sabitlenmemiş pencereler yerinde durur. *Grubu gönder* bağlı
  kuralı taşır; harita onu gölgede göstermez.
- **Plan seçici tek bir ekran değişimini izliyor** (bir takıp çıkarmadan sonra
  önceki planda kalabiliyordu).
- **Masaüstü adları öteki kurulumun planı yüzünden kaybolmuyor**; masaüstü
  hâlâ duran bir ad hiçbir zaman silinmiş sayılmaz.
- **Birincil harici monitör**: sola eklenen sanal ekran, başka sırayla yeniden
  takma ya da aynı model iki monitör Ekstra monitör düzenini artık ele
  geçirmez (hata tablolarında A/A′).
- **Yeniden açma**: paket kimliği olmayan Safari kuralları sekme değil yeni
  pencere açar; Son Kullanılanlar gibi Finder konumları yeniden açılır;
  yeniden açma taraması yönlendirmeyi bloke etmez.
- **Boşta CPU** düştü: pencereler daha seyrek taranır, başlık olayları
  süzülür, tarama bütçesi yanıtsızlık eşiğinin altında tutulur.
- **Derleyici uyarıları: 0.** `make concurrency-check` uyarıları yeniden
  sayıyor (derleyicinin renkli çıktısı onları gizliyordu); 14 olağan derleyici
  uyarısı ve bütün sıkı eşzamanlılık uyarıları (yönlendirici, pencere
  satırları, düzen sabitleri, RootView gözlemcileri) giderildi; release
  derlemesi de `-strict-concurrency=complete` de hiç uyarı vermiyor.
- Türkçe belgelerde ve değişiklik günlüklerinde GitHub'da yanlış göreli yola
  giden bağlantılar.

## Kaldırılanlar

- **Deskmap'ten önceki adın desteği**: eski veri klasörü ilk açılışta
  kopyalanmıyor, eski URL şeması kaydedilmiyor, eski profil dışa aktarma
  dosyaları içe alınmıyor.

## 0.5.0'dan yükseltme

**İzinler.** Yeni izin yok; tek izin Erişilebilirlik. macOS izni kod imzasına
bağlar: 0.5.0'daki gibi ad-hoc imzayla her güncellemeden sonra yeniden istenir
(öncekiyle aynı); 0.6.0 Developer ID ile imzalanan ilk derleme olursa bir kez
daha istenir, sonra kalır.

**İlk açılış.** Sürüm notarize edilmediyse macOS ilk açılışı 0.5.0'daki gibi
engeller: uygulamayı bir kez aç, sonra Sistem Ayarları › Gizlilik ve Güvenlik ›
**Yine de Aç**. Bkz. [indirme sayfası](https://cnkndmr.github.io/deskmap/tr/download/)
ya da README.

**Veri dosyaları.** `rules.json` ilk açılışta şema 4/5'ten **şema 6**'ya
geçer. Eski dosyalar `Backups/pre-migration/` altına kaydedilir (hiç
budanmaz); adlar sabit pencerelerinin yerine göre masaüstleriyle eşleştirilir;
yanlışlıkla oluşan silinen masaüstü satırları kaldırılır, sabitlemeleri geri
gelir. Bir kart sonucu bildirir, **N boş masaüstünü kaldır** ve **Yükseltmeyi
geri al** sunar. Yükseltme sırasında hiçbir şey taşınmaz ya da silinmez. **Eski
Deskmap yeni dosyayı salt okunur açar**; geri dönmek istersen pre-migration
kopyasından dön. Çalışma anındaki masaüstü bilgileri `desktop-state.json`'a
taşındı. Profil dışa aktarma sürüm 5 (pin grupları dahil); sürüm 3 ve 4 dosyaları yine içe alınır.
`rules.json`'a isteğe bağlı `displayRoles` alanı eklendi (eski sürümler yok
sayar).

**Yeni ayarlar.**

| Ayar | Nerede | Varsayılan | Ne yapar |
|---|---|---|---|
| Yine de dene (masaüstü taşıma) | ana penceredeki kart, `status.json` `desktopMoves` | macOS 15.x ve 26.0–26.3'te kapalı, diğerlerinde açık | masaüstü taşımayı açar; hatırlanır |
| Yedekler | Ayarlar › Yedekler | açık, otomatik | saatlik / günlük / haftalık kopya, geri yükleme |
| Monitör rolleri | ikinci monitör kartının menüsü, `deskmap screen-role` | ilk monitörden öğrenilir | hangi fiziksel monitör *Ekstra monitör* / *2. monitör* |

**Beklenecek davranış değişiklikleri.**

- *Yeni monitör bir kez sorar.* İlk monitörün öğrenilmesinden sonra Deskmap'in o
  rolde görmediği monitör beklemededir: kartta *düzen bekliyor* yazar, *Ekstra
  monitör olarak kullan* seçersin. 0.6.0 öncesinde düzen hemen oraya gidiyordu.
- *Pencereler kuralını korur.* Pencere, başlığı sonradan başka sabitlemeye
  uysa da onu yerleştiren sabitlemede kalır; yalnız kesin daha özgül bir
  sabitleme onu alabilir. Önceden en son uyan başlık kazanıyordu.
- *Masaüstü taşıma kartı.* macOS 15.x ve 26.0–26.3'te ana pencere turuncu
  bir kartla açılır, **Yine de dene** diyene kadar taşıma kapalıdır.
- *Adlar profile ve masaüstüne ait.* Adın numarası yok; yeni profil adsız
  başlar; monitör takıp çıkarmak kurulumun planını uygular, masaüstü
  oluşturabilir ya da planın dışındaki boş artıkları silebilir.
- *Geri al* artık 10 saniyelik bağlantı değil; ⌘Z bu oturumun değişikliklerinde,
  URL/CLI dâhil, adım adım geri gider.
- *İçinde pencere olan masaüstünü silmek önce sorar.*
- `profile-backup.sh` kalktı; yedekler uygulamanın içinde.

## Bilinen sınırlar

- **Notarize değil** (bakımcı yayından önce başka karar vermezse): Gatekeeper
  ilk açılışı engeller; Homebrew cask'i resmi depoda değil bakımcının kendi
  tap'inde.
- **Özel API.** Pencereyi başka masaüstüne taşımak çalışma anında çözülen
  SkyLight çağrılarını kullanır; bir macOS güncellemesi bozabilir. macOS 15.x
  ve 26.0–26.3'te doğrulanmamıştır, kapalı başlar.
- **Tek kalan bilinmeyen monitör bekler.** macOS güvenilir bir "sanal ekran"
  bayrağı vermez; yepyeni gerçek bir monitör de Ekstra monitör düzenini
  almadan önce bir kez sorar.
- **Genel başlık bekleme süresi** (başlığı uygulama adına eşit pencere
  bağlanmadan önce 8 sn bekler) seçilmiş bir değerdir; gerçek yeni oturum
  penceresiyle henüz ölçülmedi.
- **Eski Deskmap şema 6'yı salt okunur açar**; sürüm düşürmek pre-migration
  kopyasını geri yüklemek demektir.
- **Erişilebilirlik izni** uygulama ad-hoc imzalı olduğu sürece her
  güncellemeden sonra yeniden istenir.
- **Güncelleme denetimi yok**; Deskmap hiçbir sunucuya bağlanmaz. Yeni sürümü
  indirip uygulamayı değiştir ya da `brew upgrade --cask deskmap`.
- **macOS ayarları** hâlâ önemli: *Alanları en son kullanıma göre otomatik
  olarak yeniden düzenle* kapalı, *Ekranların ayrı Alanları var* açık,
  uygulamanın Dock menüsünde *Seçenekler › Ata → Hiçbiri*.
