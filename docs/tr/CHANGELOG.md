# Değişiklikler

Projedeki kayda değer bütün değişiklikler burada. Biçim
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)’a dayanır. Sürüm
numarası `VERSION` dosyasından gelir.

## [Unreleased]

### Eklenenler {#added}

- **Pin grupları.** Bir masaüstündeki pinlerin bir kısmını bir ad altında
  topla: pencerelere ve pin çiplerine (kapalılar dahil) ⌘ ile tıkla › **Grup
  olarak pinle**, ya da sağ tık › **Gruba ekle**. Grup bütün olarak taşınır
  (başlığından sürükle ya da **Grubu gönder**; dağılmış üyeler yeniden bir
  araya gelir), tek düğmeyle açılır ve kapanır, yeniden adlandırılır
  (başlığa çift tık). Tek başına taşınan pin grubunda kalır; **Gruptan çıkar**
  onu çıkarır, **Grubu dağıt** pinleri korur. Geri al her adımı kapsar. Ayrıca
  `deskmap group …` ve `deskmap://group-add`, `group-rename`, `group-remove`,
  `group-set`; `status.json` `pinGroups` listeler. Gruplar `rules.json`’da
  yeni isteğe bağlı alanlardır (`rules[].groupID`, `profiles[].pinGroups`,
  şema 6 kalır); **eski bir Deskmap dosyayı kaydederse gruplar düşer**
  (pinler kalır). Profil dışa aktarımı sürüm 5 (gruplar dahil; sürüm 4 yine
  içe aktarılır).

- **Öbür plandaki düzeni kullan.** Bir sabitlemenin iki planı pencereyi aynı
  yere (aynı ekran ve masaüstü) farklı düzenle koyuyorsa paneli öbür planın
  düzenini ve onu bir kez kopyalayan düğmeyi gösterir (⌘Z geri alır; planlar
  bağlanmaz). Komut satırından da: `deskmap rule copy-layout KURAL --from
  docked|undocked` (`deskmap://rule-copy-layout/<id>?from=`).
- **Kendi düzenlerin.** Ayarlar › Düzenler bütün düzenleri üç grupta
  listeler: **Temel** (her pinin altındaki döşemeler, en çok altı, Gelişmiş’te
  de), **Gelişmiş** (ızgaranın yanında) ve **Gizli**. Izgarada ya da kenar
  boşluklarıyla yeni düzen çiz, ad ver, normal ya da ultra geniş ekranlarla
  sınırla, hazır düzenleri değiştir ya da yeniden adlandır, ↑ ↓ ile sırala,
  **Varsayılanlara dön…**. Gelişmiş’te hazır düzenlerin altındaki **Düzenleri
  düzenle…** sekmeyi açar. Pinler düzenin değerini tutar; düzeni değiştirmek
  ya da silmek hiçbir pencereyi taşımaz, adlandırılmış düzene uyan pin o adı
  gösterir. `rules.json`’da (`layouts`, bütün profillerde ortak) durur,
  yalnız değişince yazılır; geri alınabilir. Yedeği geri yüklemek onun
  düzenlerini getirir; düzensiz yedek şu ankileri korur.
- **Mission Control’de başka ekrana sürüklenen masaüstü geri gelir.**
  Deskmap eski yere masaüstü ekler, pencereleri oraya taşır, sürükleneni
  boşsa siler; ad izler, pinler değişmez, kart **Böyle kalsın** sunar.
  Ayarlar › Genel: **Geri al** (varsayılan) / **Sor** / **Bırak**. Ekran
  değişiminden sonra, uyanınca, açılışta (bunun yerine kart sorar) ya da
  masaüstü taşıma kapalıyken (kart söyler) yapılmaz. `docs/tr/bug-tables.md`
  Tablo E.
- **Demo GIF.** `docs/media/<dil>/demo.gif` (ve `.mp4`) README ile kılavuzdaki
  dört adımlık hikâyeyi gösterir: sadece laptop, monitör bağlandı, sabitlenen
  pencereler yerinde, kendi rolüyle ikinci monitör. Ekran görüntüsü kipi çizer
  (`Deskmap --shots <dizin> --scenario demo`, demo verisi, gerçek pencereye
  dokunulmaz), `make demo-media` (ffmpeg) birleştirir; İngilizce ve Türkçe.
- **Doğrulanmamış macOS sürümlerinde masaüstü taşıma kapalı.** Pencereleri
  masaüstleri arasında taşımanın doğrulanmadığı macOS 15.x ve 26.0–26.3’te
  masaüstü taşıma kapalı başlar ve ana pencerede bunu söyleyen bir kart
  görünür (ekran ve düzen yine uygulanır). **Yine de dene** taşımayı açar ve
  hatırlanır; devre kesici her taşımayı izlemeye devam eder
  (`Services/MoveSupport.swift`). `status.json` durumu `desktopMoves` olarak
  yazar, taşıma kapalıysa `deskmap status` bunu bir satırla söyler.
- **CLI birim testleri.** `make cli-test`, `deskmap` komut satırı aracının
  çevrimdışı testlerini koşar (düzen ayrıştırma, düzen dosyaları, birleştirme,
  eşleştirme, `check` raporu); CLI değişince pre-commit kancası da koşar.
- **Birden çok monitörde sıralı yerler.** Monitör bağlı kurulumda bir
  sabitlemenin monitör başına bir yerden oluşan sıralı bir listesi vardır:
  sabitlenmiş pencereyi başka bir monitöre bırakınca eski yeri yenisinin
  altında kalır; bağlı monitördeki yer, şu an takılı olmayan bir monitörün
  önüne geçmez. Monitörü bağlı ilk yer kazanır; böylece 2. monitör
  çıkınca pencereleri eski yerlerine döner. Hiçbiri bağlı değilse pencere rol
  sırasında bağlı ilk monitöre, ilk yerinin masaüstü numarasıyla gider.
  `rules.json` ilk yeri `docked`’ta tutar (eski sürümler onu okur), kalanları
  yeni, isteğe bağlı `dockedNext` alanında (şema 6 değişmedi). Düzen dosyaları
  `docked: [external-2/1, external/2]` kabul eder; `status.json` pencereleri
  `place` taşır (`"1"`, `"2"` …, `"fallback"`, `"untouched"`). Tasarım tablosu:
  `docs/tr/bug-tables.md` §D. Haritada takılı olmayan monitör ötekilerin altında
  soluk, kesik çizgili bir karttır (model adı, *bağlı değil*, son görülen
  masaüstü sayısı); onu bekleyen sabitlemeler kesik çerçeveli çiplerde durur,
  oraya pencere bırakmak ona yer verir. Sabitleme paneli yerleri listeler (↑ ↓ ×,
  kullanılan vurgulu, yedek notu), *Neden burada?* kazanan yeri söyler. Yeni
  monitörün kartında **Sıranın sonuna ekle** ve **Yerine geç…** var; kart başlığı
  menüsü yalnız Deskmap'in gördüğü monitörleri listeler.
- **İkinci harici monitör.** Her harici monitör rolünü (*Ekstra monitör*,
  *2. monitör*, …) soldan sağa konumuyla değil ekran UUID’siyle korur: ekranların
  yerini değiştirmek, onları başka sırayla takmak, sola eklenen sanal ekran ya
  da aynı model iki monitör artık sabitlemeleri öteki monitöre kaydırmaz. İki ya
  da daha çok monitör bağlıyken ikinci kartın başlığı onları (onayla) yer değiştiren bir menüdür;
  `deskmap screen-role`, `deskmap screen-role --forget` ve `screen-role`,
  `screen-role-forget` URL komutları aynısını yapar. İki monitörün yerini
  değiştirmek düzenlerini de değiştirir; bağlı olmayan bir kart da
  değiştirilebilir. `rules.json`’a
  isteğe bağlı `displayRoles` alanı eklendi (şema 6 değişmedi; eski sürümler onu
  yok sayar ve konum sırasına döner). `status.json` ekranları `uuid` taşır
  (`Models/DisplayRoles.swift`).
- **Deskmap’in hatırlamadığı monitör bekler.** İlk monitör öğrenildikten sonra
  rolünde hatırlanmayan ekran (yeni monitör, tek kalan sanal ekran, unutulan
  monitör ya da aynı rolde hatırlanan iki monitörden eskisi) beklemededir: ona
  plan, sabitleme ya da kural uygulanmaz, orada artık temizliği yapılmaz; Ekstra
  monitör düzeni kendiliğinden taşınmaz. Kartında *yeni monitör · düzen
  bekliyor* ve bir menü görünür (*Ekstra monitör / 2. monitör … olarak kullan*,
  onaylı; hatırlananlarda *Bu monitörü unut*). `deskmap screen-role EKRAN
  --forget` ve `deskmap://screen-role-forget/<monitör>` tek monitörü unutur;
  `deskmap screens` *role on hold* gösterir; `status.json`’a `heldRoles`,
  `displayRoles`’a `learnedOnce` eklendi (docs/tr/bug-tables.md, A′ tablosu).

- **Bir çalışma alanını tek seferde aç.** Kapalı sabit pencereleri olan bir
  masaüstünün adının yanında **N aç** görünür (liste ve görsel görünümde);
  tek tık hepsini açar, her biri kendi sabit yerine gider. Her uygulama
  grubunun başlığının sağında düğmeler var: **↗** grubun kapalı sabit
  pencerelerini açar (yarısı açık bir grup önce tamamlanır), **✕** grubun
  bütün sabit pencerelerini kendi kapatma düğmesiyle kapatır (uygulama
  çalışmaya devam eder, sabit olmayan pencerelere dokunulmaz, kaydedilmemiş
  belgeler yine sorar). Her uygulamada çalışır (`Services/PinBatch.swift`).

- **Zamanlı pinler kutusu.** Bir süre serbest bırakılan sabit pencereler sol
  kenar çubuğunun altında kendi kutularında listelenir; süresi en önce biten
  başta, yanında **Hepsini bitir** düğmesi. Hiç yoksa kutu gizlenir.
- **Çok adımlı geri al / yinele ve değişiklik geçmişi.** Bu oturumdaki her
  ayar değişikliği bir adımdır (en çok 50, kaydedilmez): ⌘Z / ⇧⌘Z ve alt
  çubukta hep duran ↶ ↷ düğmeleri, 10 saniyelik “· Geri al” bağlantısının
  yerini alır. Son hareketler’e iki sekme geldi: **Değişiklikler** (yeni: en
  yenisi başta, ● ŞİMDİ, yinelenebilen soluk satırlar, **Buraya dön**) ve
  **Pencere hareketleri** (eski liste). URL komutlarından, CLI’dan, profil
  değiştirmeden ya da Mission Control’den gelen değişiklikler artık geri
  almayı iptal etmek yerine birer adım olur. Geri aldıktan sonra yapılan yeni
  bir değişiklik yineleme dalını atar; alt çubukta çıkan uyarıdaki Geri al onu
  geri getirir. Geçici sabitleme adımları yalnız geri alınabilir
  (`Models/ChangeHistory.swift`).
- **Otomatik yedekler**: uygulama bütün profilleri, sabitlemeleri ve masaüstü
  adlarını `Application Support/Deskmap/Backups/` altına saatlik (24 saat
  saklanır), günlük (7 gün saklanır) ve haftalık (sonsuza dek saklanır) olarak
  yedekler. **Ayarlar › Yedekler**’den (profil panelindeki **Yedekler…** ile de)
  ya da `deskmap backups` / `deskmap backup-restore <id>` ile geri getir;
  şimdiki hâl önce yedeklenir ve geri getirme geri alınabilir. Dışarıdaki
  `profile-backup.sh` betiğinin yerini alır.

### Değişenler {#changed}

- **Belgeler web sitesinde**: tek sayfalık rehber `docs/site/` kalktı; İngilizce guide ile
  Türkçe kılavuz, başvuru, mimari, gizlilik ve bu değişiklik günlüğü `make site` ile
  web sitesine derlenip GitHub Pages’e yayımlanıyor
  (`.github/workflows/pages.yml`).

- **Harita penceresinin yerleşimi**: her açılışta bir kez yerleşir; yüksekliği
  sabittir ve ekranın görünür alanına sığar, dahili ekranın üst ortasına
  oturur, boyutu ayarlandıktan sonra görünür ve yeniden boyutlandırmadan sonra
  sistemin kaydırmalarıyla artık oradan oraya itilmez.

- **Masaüstü adları v2 (`rules.json` şema 6)**: bir ad artık tek bir fiziksel
  masaüstüne aittir ve ekranlar arasında, sıralama değiştiğinde ve monitör
  takılıp çıkarıldığında onu izler; artık planı, ekranı ya da numarası yok. Her
  profilin her kurulum için bir planı var (hangi ad nerede, her ekranda kaç
  masaüstü). Monitörü takınca ya da çıkarınca yeni kurulumun planı uygulanır:
  adlı masaüstleri bütün pencereleriyle birlikte taşınır, bir monitör
  masaüstündeki adsız pencereler laptop masaüstlerine park edilir ve monitör
  yeniden takılınca (başka bir monitör olsa da) geri döner, eksik masaüstleri
  oluşturulur ve yalnız planın dışında kalan boş masaüstleri silinir (her biri
  silinmeden hemen önce boş mu diye yeniden denetlenir). Ekran değişikliği
  yüzünden kaybolan bir masaüstü artık silinen masaüstü satırı olmaz; bu
  satırlar yalnız gerçek silmelerden gelir. Profil değiştirmek ve **Sadece
  laptop planını buraya kopyala** pencereleri plana uyacak şekilde taşır ama
  hiçbir masaüstünü silmez. İçinde pencere olan bir masaüstünü silmek artık
  önce sorar.
- **Sabitleme bir adı hedef alabilir**: sabitleme paneli ve **Gönder** önce
  adları listeler; sabitleme adlı masaüstünü izler ve adın masaüstü yokken
  bekler (hiçbir şey taşınmaz). `deskmap://pin/<window>?name=<name>` de aynısını
  yapar.
- **Şema 5’ten yükseltme** ilk açılışta yapılır: eski dosyalar
  `Backups/pre-migration/` altına kaydedilir (hiç budanmaz), adlar sabit
  pencerelerinin bulunduğu yere göre masaüstleriyle eşleştirilir, yanlışlıkla
  oluşmuş silinen masaüstü satırları kaldırılır ve sabitlemeleri geri getirilir.
  Bir kart sonucu bildirir ve **N boş masaüstünü kaldır** ile **Yükseltmeyi
  geri al** seçeneklerini sunar. Yükseltme sırasında hiçbir şey taşınmaz ya da
  silinmez; eski bir Deskmap yeni dosyayı salt okunur açar.
- `deskmap desktops` adları, her kurulum için canlı yerleri ve planlanan
  yerleriyle birlikte, planları da listeler; `status.json`’a `names` ve `plans`
  eklendi. Profil dışa aktarma sürüm 4 oldu (masaüstü kimliği olmadan adlar ve
  planlar); sürüm 3 dosyaları yine içe aktarılır. Çalışma anındaki masaüstü
  bilgileri `desktop-state.json`’a taşındı.
- `deskmap://quit` uygulamayı kapatır, `DESKMAP_DATA_DIR` onu başka bir veri
  klasörüne yönlendirir; betikler ve testler için.

- **Masaüstü adları profile ait**: adlar, bağlı oldukları masaüstleri,
  silinen masaüstü satırları ve planlanan masaüstleri artık her profilde ayrı
  tutulur. Yeni bir profil adsız başlar, bir profilde yeniden adlandırmak
  ötekini hiç değiştirmez, profil değiştirince hedef profilin adları hemen
  görünür ve yalnız eksik planlı masaüstleri oluşturulur. Çoğalt onları da
  kopyalar; dışa / içe aktarma adları ve planlı masaüstlerini taşır. Mission
  Control’deki taşıma ve silmeler her profili günceller; silinen bir masaüstüne
  ad vermiş her profil kendi silinen masaüstü satırını alır. `rules.json` şema
  5: eski dosyalar kullanıma göre bölünür (bir ad yalnız o masaüstünde
  sabitlemesi olan profillere gider); eski bir Deskmap yeni dosyayı salt okunur
  açar.
- **Sadece laptop planını buraya kopyala** (⋯ menüsü) laptop masaüstlerinin
  adlarını da Monitör bağlı planına kopyalar (aynı ad o planın başka bir
  yerindeyse kaldırılır), laptop masaüstlerinin bağlarını korur, planı
  büyütür ve laptop kurulumunda yalnız masaüstü adları ya da planlı masaüstleri
  olsa da çalışır. Kopyalanan ekranlarda etkin profilin sıradaki masaüstü
  silmeleri temizlenir; öteki profillerin sıradaki silmeleri kalır.
- Boş bir masaüstü numarası bulamayan ad (masaüstü hâlâ duruyorsa) artık
  kaybolmak yerine kendi profilinde yalnız addan oluşan bir silinen masaüstü
  satırında kalır; hiçbir sabitleme taşınmaz.

### Kaldırılanlar {#removed}

- **Deskmap’ten önceki adın desteği**: eski veri klasörü ilk açılışta artık
  kopyalanmıyor, eski URL şeması artık kaydedilmiyor ve eski profil dışa
  aktarma dosyaları artık içe aktarılmıyor (`DataMigration` ve testleri
  kaldırıldı).

### Düzeltilenler {#fixed}

- **Plan ya da monitör seçiminden hemen sonra pencereler taşınıyor.** Masaüstü
  planının sonunda (monitör takıldı, rol takas edildi ya da onaylandı) yeniden
  yerleştirme taraması plan hâlâ sürüyor sayılırken çalışıyordu; yönlendirme
  tutuluyor, ardından tarama gelmiyordu: rol takasından ya da monitör onayından
  sonra pencereler bir sonraki tam taramayı (en çok iki dakika) bekliyordu.
  Tarama artık plan bittikten sonra çalışıyor. `scripts/hooktest/places.sh`
  buldu.
- **İki sanal test ekranı artık gerçek monitör sanılmıyor.** macOS ikincisini
  "Deskmap Test Display (1)" diye adlandırıyor; o da tanınıyor.

- **Plan seçici tek bir ekran değişimini izliyor.** Monitör bir kez takılıp
  çıkarılınca seçici önceki planda kalabiliyordu: ekran listesi henüz
  yayınlanırken ekran modunu okuyordu. Artık yayınlanan listeyi izliyor
  (`docs/bug-tables.md` A′).
- **Uygulama grubunu taşımak ve haritadaki gölgede kalan pinler pencerenin
  bağını izliyor.** Pencere başlığı değişse de onu yerleştiren kuralda
  kalır; *Grubu gönder* artık yeni başlığın uyduğu kuralı değil o kuralı
  taşır, harita da bağlı kuralı yenik göstermez.
- **`make concurrency-check` uyarıları yeniden sayıyor.** Derleyici çıktısını
  renklendirdiği için uyarı deseni hiçbir satıra uymuyor, sayı hep 0
  çıkıyordu.
- **Türkçe belgelerde ve değişiklik günlüklerinde** GitHub’da yanlış göreli
  yola giden bağlantılar.

- **Masaüstü adları artık öteki kurulumun planı yüzünden kaybolmuyor.** Etkin
  olmayan kurulumdan bir laptop masaüstü satırını silmek, etkin kurulumun aynı
  ve sonraki numaralardaki adlarını hemen atıyordu (sabitlemeleri kalıyordu);
  artık adlar, silme gerçekten yapıldığında sabitlemeleriyle birlikte kayar.
  Başka bir yerde (öteki kurulumda ya da monitörde) adı olan bir laptop
  masaüstü, boş göründüğü bir plandan silinmek üzere artık sıraya konamaz.
  Öteki kurulumun sıradaki silmeleri artık canlı adlı masaüstlerini silinmiş
  göstermiyor (bu, onları silinen masaüstü satırına çeviriyor, sabitlemelerini
  ve öteki kurulumdaki karşılıklarını da beraberinde götürüyordu); masaüstü
  hâlâ duran bir ad hiçbir zaman silinmiş sayılmaz.

## [0.5.0] — 2026-09-30

İndirilebilen ilk sürüm: [sürümler sayfasında](https://github.com/cnkndmr/Deskmap/releases)
evrensel bir `Deskmap.app`. Haritaya bir kenar çubuğu ve bir düzen ızgarası
geldi, sabit pencereler bir süre serbest bırakılabiliyor, masaüstleri
haritadan eklenip silinebiliyor ve yeniden sıralanabiliyor, menü çubuğu simgesi
de kullandığın pencereyle açılıyor.

### Eklenenler {#added-2}

- **Sağ tık menüsü**: önde sabit bir pencere varken menü çubuğu simgesine sağ
  tıklayınca haritayı açmadan onu serbest bırakabilirsin: *Serbest bırak*
  paneldeki sürelerin aynısını listeler. Pencere serbestken menü kalan süreyi
  ve *Şimdi bitir*’i gösterir. Önde sabit pencere yoksa sağ tık eskisi gibi
  hiçbir şey yapmaz.
- **Kullandığın pencereyle açılır**: menü çubuğu simgesine tıklayınca en son
  tıkladığın pencere, satırına tıklamışsın gibi seçilir: harita ona kayar ve
  paneli açılır (sabitleme ayarları ya da sabitlemesi yoksa bir sabitleme
  taslağı). Geçen seferden açık kalan bir panel artık ilgisiz bir pencerede
  kalmıyor. Taslak açıkken, sen kendin bir düzen seçene kadar pencerenin boyutunu
  ve konumunu izler.
- **Menü çubuğu rozeti**: menü çubuğu simgesi, iki kurulumda da sabitlemesi
  olmayan açık pencerelerin sayısını gösterir (*Yeri olmayan pencereler*
  sayısı; dokuzun üstünde 9+, sıfırda hiçbir şey). Rozet şablon simgeye
  oyulmuştur, bu yüzden açık ve koyu menü çubuklarına uyar; VoiceOver sayıyı
  okur. Tam ekran pencereler sayılmaz.
- **Düzen ızgarası**: düzen düzenleyicisi hedef ekranı gerçek biçimiyle bir
  ızgara olarak çizer (12 × 8 hücre, ultra geniş ekranlarda 24 × 6); bir alan
  seçmek için üzerinde sürükle. İnce ayar için yüzde alanları duruyor.
- **Ekran biçimine göre hazır düzenler**: ultra geniş ekranlar üçte birler,
  üçte ikiler, çeyrekler ve ortada bir yarım alır; öteki ekranlar yarımlar, iki
  yanda 70 / 30 ve 30 / 70, üst ve alt yarılar, köşeler ve orta alır. Her hazır
  düzen listesi ayna simetriğidir (bir test bunu denetler).
- **Sabit boyut**: bir düzen, dokuz yaslama noktasından birinde nokta
  cinsinden bir boyut olabilir (ör. 1400 × 900); her ekranda aynıdır, daha
  büyükse kullanılabilir alana sığdırılır. Açınca şu anki alan korunur (kenardan
  kenara boyutlar tam olarak) ve yaslama noktası, değdiği kenarlardan seçilir.
  Bir uygulama boyutu reddederse pencere yine de yaslama noktasına, uygulamanın
  kabul ettiği boyutla yerleşir. *Şu anki boyutu ve konumu kullan* sabit bir
  düzeni sabit tutar. Eski kural dosyaları değişmeden okunur; rules.json artık
  şema 4, böylece eski bir Deskmap sabit boyutları atmak yerine dosyayı salt
  okunur açar, her sabit düzen de eski okuyucular için oransal karşılığını
  saklar.
- **Pencere sabitleme paneli için büyür**: bir pencereye ya da sabitlemeye
  tıklayınca paneli haritanın altında açılır ve pencere aşağı doğru büyür;
  harita yüksekliğini korur. Yalnız ekran yetmeyecek kadar kısaysa fark
  haritadan gider.
- **Kenar çubuklu, daha geniş harita**; boyutu açıldığı ekrana göre ayarlanır
  (kullanılabilir alanın %53 × %70’i, 660–1100 × 480–900 pt, hiçbir zaman
  ekrandan büyük değil; kullanılabilir alanı 1710 × 1074 pt olan bir ekranda
  yaklaşık 900 × 750). *Yalnız bir planda yeri olanlar* ve *Yeri olmayan
  pencereler* hep görünen bir sol kenar çubuğunda durur; böylece bir pencere
  bütün haritayı yukarı tırmanmak yerine yana, bir masaüstüne sürüklenir.
- **Sürüklerken kendiliğinden kaydırma**: sürüklenen bir öğeyi haritanın üst ya
  da alt kenarına yakın tutunca harita kayar, kenara ne kadar yakınsa o kadar
  hızlı; harita kayarken de imlecin altındaki masaüstü vurgulanır. Kenar
  şeridinin içinde başlayan bir sürükleme, ancak şeridi bir kez terk ettikten
  sonra kaydırır.
- **İki kenar çubuğu kutusu.** *Yalnız bir planda yeri olanlar*, yalnız
  öteki kurulumda ya da yalnız bu kurulumda sabit olan veya öteki kurulumda
  başka bir ekrana ya da masaüstüne gönderilen sabitlemeleri listeler (o yer de
  gösterilir). *Yeri olmayan pencereler* (iki kurulum sekmesinde de,
  daraltılabilir), iki kurulumda da sabitlemesi olmayan açık pencereleri
  listeler; şu anki kurulumun sekmesinde birini sürüklemek onu bir kez taşır,
  öteki kurulumun sekmesinde bırakmak (ya da raptiye düğmesine basmak) o kurulum
  için bir sabitleme açar ve pencereyi taşımaz.
- **Serbest bırak**: sabit bir pencerenin panelinde bir zamanlayıcı düğmesi var
  (1, 5, 15, 30 ya da 60 dakika). Bu süre boyunca Deskmap pencereyi yerine
  koymaz, yani pencere serbestçe taşınıp yeniden boyutlandırılabilir; satır
  kalan süreyi gösterir, “+5 dk” süreyi uzatır, “Şimdi bitir” durdurur. Süre
  dolunca sabitleme yeniden uygulanır (masaüstü ve düzen). Kaydedilmez;
  pencere kapanınca biter, pencerenin sabitlemesi kaldırılınca ya da
  değiştirilince (taşındı, yeni düzen, başka profil ya da kurulum) erken
  biter, böylece yeni sabitleme hemen uygulanır.
- Bağlı her ekranın altındaki “+ Masaüstü N” satırı artık tıklanınca gerçek
  bir masaüstü ekler: Mission Control bir anlığına açılır, Deskmap o ekranın
  **+** düğmesine Erişilebilirlik üzerinden basar ve Mission Control’ü yeniden
  kapatır. Aynısı `deskmap://add-desktop/<screen>` ile de yapılabilir. macOS
  26’da Mission Control’ün ağacı Dock’ta değil `WindowManager`’da duruyor
  (ölçüldü); ikisi de aranır.
- “+ Masaüstü N” etkin olmayan kurulumda da çalışır (ör. monitör bağlıyken
  Sadece laptop): masaüstü planlanır (“henüz yok” olarak gösterilir, sabitleme
  alabilir, ⌘Z geri alır, sağ tık son boş olanı siler) ve o kurulum etkin
  olunca Deskmap eksik masaüstlerini Mission Control üzerinden oluşturur.
  Planlar her kurulum ve ekran için `rules.json`’da (`plannedDesktops`)
  saklanır.
- Masaüstleri silinebilir: etkin kurulumda bir masaüstü satırına sağ tıkla →
  “Masaüstünü sil (N)” (ya da `deskmap://remove-desktop/<screen>/<n>`). Mission
  Control onu siler (`AXRemoveDesktop`); sonraki masaüstlerindeki sabitlemeler
  bir yukarı kayar, silinen masaüstündekiler bir önceki masaüstüne geçer,
  oturum sabitlemeleri de dahil. Bir ekranın son masaüstü hiçbir zaman
  silinmez, Mission Control’ün listesi SkyLight’ınkiyle uyuşmazsa hiçbir şeye
  dokunulmaz ve ⌘Z yoktur (masaüstünün kendisi geri getirilemez).
- Artık her masaüstü satırında, iki kurulumda da, başka hiçbir sınır olmadan
  “Masaüstünü sil (N)” var. Etkin olmayan kurulumda silme sıraya alınır
  (`rules.json`’da `pendingRemovals`, ekran bağlıysa Alan kimliğiyle) ve o
  kurulum etkin olunca Mission Control üzerinden yapılır; sabitlemeler hemen
  kayar ve ⌘Z bunu geri alır. Laptop ekranının masaüstleri iki kurulumda
  ortaktır, bu yüzden birini hemen silmek onu etkin kurulumdan da silerdi.
  Yalnız plan ya da sabitleme olarak var olan satırlar sadece yeniden
  numaralanır. Ayrı duran “Bu planlı masaüstünü sil” öğesi kaldırıldı.
- Etkin kurulumda bir masaüstü satırını sürüklemek artık masaüstlerini
  gerçekten yeniden sıralıyor: o ekrandaki her pencere (sabit olsun olmasın;
  “Tüm Masaüstleri” pencereleri yerinde kalır) masaüstünün yeni konumuna
  taşınır. macOS, Alanları dışarıdan yeniden sıralamanın bir yolunu sunmuyor
  (Mission Control’de böyle bir eylem yok, SkyLight çağrısı SIP’in kapalı
  olmasını istiyor), bu yüzden onun yerine içerik taşınır. ⌘Z onları geri
  taşır.
- Tam ekran ve Split View alanları artık haritada salt okunur mor satırlar
  olarak, masaüstlerinin arasında Mission Control’deki gerçek konumlarında
  görünüyor. Eskiden tam ekran alanındaki bir pencere haritadan tamamen
  kayboluyordu.
- `appstore/probe/`: Erişilebilirlik API’sinin App Sandbox içinde çalışıp
  çalışmadığını ölçen iki derlemeli (sandbox’lı ve sandbox’sız) bir deneme.
  macOS 26.6.2’deki sonuç: izin verilmiş olsa bile sandbox’lı derleme başka bir
  uygulamanın pencerelerini okuyamıyor (−25204), yani Deskmap’in Mac App Store
  sürümü pencere yerleştiremez. `docs/distribution.md` ve
  `appstore/submission.md` artık bu ölçümü kaynak gösteriyor. Yarım kalan
  mağaza sürümü (özel API kullanmayan bir `APPSTORE` derleme bayrağı)
  `deskmap-appstore` dalında bekliyor.

### Değişenler {#changed-1}

- App Store malzemesi tek bir klasörde, `appstore/` altında: gönderim kontrol
  listesi (eskiden `docs/app-store-submission.md`), mağaza sayfası metni
  (eskiden `docs/listing.md`), ekran görüntüsü betiği (eskiden
  `scripts/make-store-shots.swift`) ve çıktısı `appstore/screenshots/`,
  bir de sandbox denemesi.

### Düzeltilenler {#fixed-1}

- Az önce kullandığın pencerenin satırını başka bir ekrandaki bir masaüstüne
  sürükleyince harita artık kapanmıyor. Pencere ekran değiştirirken macOS
  odağı ona geri veriyordu; artık bir satır ya da çip sürüklenirken Deskmap öne
  geçiyor ve harita kapanınca odağı geri veriyor.
- Bir pencereyi sürüklemeye başlamak artık haritayı bir satır aşağı itmiyor:
  sürükleme ipucu alt çubuğa taşındı, böylece hafifçe kayan bir tık pencereyi
  (ya da sabitlemesini) yukarıdaki masaüstüne bırakamaz.
- Açık bir sabitleme taslağı, pencere başka bir masaüstüne geçtiğinde (canlı
  haritada sürüklenerek ya da Deskmap dışında taşınarak) artık pencereyi
  izliyor; eskiden *Sabitle* eski masaüstünü kaydedip pencereyi geri
  çekiyordu.
- Uygulamasının son taranmasından kısa süre sonra açılan bir pencere, başka bir
  masaüstüne geçtiğinde artık 30 saniyeye kadar haritadan ve kenar çubuğundan
  düşmüyor; yalnız taramanın bulamadığı pencereler bir sonraki yeniden taramayı
  bekliyor.
- Boyutunu uygulamanın reddettiği oransal bir düzen (en küçük boyutu ör. *Sağ
  %30* ya da *Alt yarı*’dan büyük olan) pencereyi ekranın sağ ya da alt
  kenarından taşmış hâlde bırakıyordu; artık pencere, sabit boyutlarda zaten
  olduğu gibi, uygulamanın kabul ettiği boyutla kullanılabilir alanın içine
  geri çekiliyor.
- Harici bir ekranın üst kenarına değen düzenlerden her açılıştan sonra
  vazgeçiliyordu (“did not take layout … in 6 attempts”), ortalanmış sabit
  boyutlar da yarım menü çubuğu kadar yukarıda duruyordu: ilk ekran ölçümü,
  uygulama açılışını bitirmeden, harici ekranın kullanılabilir alanı hâlâ tam
  çerçeve olarak (menü çubuğu düşülmeden) gelirken yapılıyordu ve bir sonraki
  ekran değişikliğine kadar kimse yeniden ölçmüyordu. Kullanılabilir alan artık
  açılış bitince ve kısa bir süre sonra yeniden ölçülüyor; bir değişiklik bütün
  sabitlemeleri yeniden uyguluyor. Gerçek bir 5120 × 1440 ekranda sabit boyutlu
  sabitlemeler denenirken bulundu.
- Sıraya alınmış bir masaüstü silme ya da bir masaüstü planı, aynı kurulum,
  ekran ve sayı için oturum başına yalnız bir kez çalışıyordu: başarılı
  olduktan ya da bir ekran değişikliğiyle yarıda kesildikten sonra aynı istek
  bir sonraki açılışa kadar sessizce atlanıyordu. Artık yalnız gerçek bir hata
  yeniden denemeyi engelliyor.
- Bugünkü masaüstü özellikleri için gözden geçirme düzeltmeleri (çok ajanlı
  gözden geçirme; her bulguyu iki ayrı şüpheci gözden geçirici doğruladı):
  - Mission Control üzerinden ekleme/silme, “Ekranların ayrı Alanları var”
    (Displays have separate Spaces) kapalıyken başarısız oluyordu (ekran
    “Main” olarak bildiriliyor); artık ana ekranın UUID’si iletiliyor.
  - Escape, Mission Control hiç açılmadığında bile gönderiliyor ve öndeki
    uygulamaya ulaşıyordu; artık yalnız Mission Control’ün ağacı açıkken
    gönderiliyor.
  - Başarısız olan sıradaki bir silme, sabitlemeler çoktan kaymış olmasına
    rağmen bütün sırayı temizliyordu; artık sıradan yalnız tamamlanan (ya da
    kaybolan) girdiler çıkıyor, hata bildiriliyor ve bir sonraki açılışta
    yeniden deneniyor. Sıradaki bir silmeyi yürütmek artık oturum
    sabitlemelerini ve öteki kurulumun sabitlemelerini de kaydırıyor.
  - Bir masaüstünü silmek yalnız etkin profili ve kurulumu yeniden
    numaralıyordu; artık her profili, canlı bir silme de o ekranın her
    kurulumunu yeniden numaralıyor (laptop ekranının masaüstleri ortak).
  - Bir plan kalıcı bir alt sınır olarak kalıyor ve kullanıcının sonradan
    sildiği masaüstlerini yeniden oluşturuyordu; artık plan karşılanınca
    temizleniyor ve oluşturma, ekranlar yatışmadan önce alınmış bir anlık
    görüntü yerine canlı sayıyı yeniden okuyor.
  - Bir masaüstünü gerçek masaüstlerinin ötesindeki plan/sabitleme satırlarına
    sürüklemek iki masaüstünün pencerelerini birleştiriyordu; artık pencereler
    yalnız gerçek masaüstleri arasında taşınıyor, bulundukları masaüstünü canlı
    okuyor (hızlı ikinci sürükleme ya da ⌘Z) ve ⌘Z yalnız pencereler gerçekten
    taşındıysa kaydediliyor.
  - Uzak pencere taraması, takılan bir uygulamada bir taramayı (sweep)
    durdurabiliyor ve her yardımcı pencere için 1000 IPC çağrısını
    yineleyebiliyordu: artık uygulama başına 30 saniyede bir çalışıyor (tek
    geçiş her pencereyi önbelleğe alıyor, ölçülen ~60–100 ms), bir zaman
    aşımında ya da 0,3 saniyelik bütçe dolunca duruyor ve o taramada zaten
    yavaş olan uygulamaları atlıyor. Uygulamalar başka masaüstlerindeki
    pencereler için AX öğelerini her zaman tutmuyor, bu yüzden bazı pencereler
    yine kaçabilir (alt-tab-macos’taki sınırın aynısı).
  - Ekleme/silme/plan işlemleri sıraya konuyor; başarısız bir “+” bildiriliyor.
- Görünmeyen masaüstlerindeki birçok pencere haritada yoktu ve yerine
  gönderilemiyordu (Claude, ChatGPT, Finder…; sabitlemeleri “açık pencere yok”
  olarak görünüyordu). AX uzak belirteci, bir AX öğe kimliğinin olması gereken
  yerde pencere numarasını taşıyordu; artık öğe kimliklerini tarıyor
  (alt-tab-macos yöntemi), yalnız `AXWindow` öğelerini kabul ediyor (alt
  öğeler aynı pencere numarasını döndürüyor), kimlikleri önbelleğe alıyor ve
  bulunamayan bir pencereyi 30 saniyede bir yeniden deniyor (tarama başına
  ~20 ms, ölçüldü).
- Masaüstü 1’deki hayalet pencereler: hiçbir Alan’da olmayan bir yardımcı
  pencere (cmux 64 pt’lik görünmez bir tane tutuyor) çerçeveye dayalı yedek
  yöntemle “Masaüstü 1”e konuyordu; bu yüzden uygulama, gerçek penceresi başka
  bir masaüstündeyken orada açık görünüyordu. Alan listesi boş okunan
  pencereler artık haritanın ve yönlendirmenin dışında bırakılıyor; gizlenmiş
  (⌘H) ve küçültülmüş pencereler Alanlarını koruyor ve görünmeye devam ediyor
  (macOS 26’da ölçüldü).
- Birden çok masaüstündeki bir pencere (“Tüm Masaüstleri”) artık hep ilk
  masaüstünde değil, o ekranda o an görünen masaüstünde gösteriliyor.
- Alanları bilinen ama hiçbir masaüstüne uymayan bir pencere artık çerçevesine
  bakılarak tahminen Masaüstü 1’e konmuyor.

## [0.4.0] — 2026-09-16

Uygulamayı başkasının eline verilebilir hâle getiren sürüm: İngilizce
konuşuyor, bir kılavuzu ve ekran görüntüleri var, adı da ne yaptığını
söylüyor.

### Eklenenler {#added-3}

- Türkçe çevirisiyle birlikte İngilizce arayüz. Kullanıcının gördüğü bütün
  metinler (pencere, kartlar, paneller, ipuçları, VoiceOver etiketleri, alt
  çubuktaki hatalar, geri alma etiketleri, dosya pencereleri) İngilizce
  anahtarlarla `L("…")` üzerinden geçiyor; Türkçe tablo
  `app/Resources/tr.lproj/Localizable.strings`. Uygulama macOS’un dil
  sırasını izler, bulamazsa İngilizceye döner. `build-app.sh` `.lproj`
  klasörlerini kopyalar, `CFBundleDevelopmentRegion = en` ve
  `CFBundleLocalizations = [en, tr]` değerlerini bildirir.
  `LocalizationTests` her anahtarın çevrildiğini, hiçbir çevirinin eskimiş ya
  da yinelenmiş olmadığını ve biçim belirteçlerinin uyduğunu denetler.
- Belgeler: README İngilizce olarak yeniden yazıldı (kurulum, gereken macOS
  ayarları, hızlı başlangıç, sabitlemeler/profiller/planlar, URL şeması,
  kısayollar, sorun giderme, mimari, geliştirme, sınırlar) ve
  `docs/architecture.md` eklendi (tarama adımları, yeniden deneme sınırları,
  veri biçimleri, yerelleştirme, testler).
- İki dilde kullanıcı kılavuzu: `docs/guide.md` ve `docs/kilavuz.md` yeni bir
  kullanıcıyı kurulumdan ilk sabitlemeye on dakikada, ekran görüntüleriyle
  götürür; `docs/site/index.html` aynı kılavuzun tek sayfalık hâlidir, EN/TR
  düğmesi ekran görüntülerini de değiştirir.
- `docs/privacy.md` (hiçbir şey toplanmaz, gönderilmez ya da kayda geçmez;
  pencere başlıkları kayda hiç ulaşmaz) ve `docs/distribution.md` (Mac App
  Store’un bu uygulamaya neden kapalı olduğu: sandbox Erişilebilirlik yazma
  API’sini engeller, pencereleri Alanlar arasında taşımak da SkyLight’ın özel
  çağrılarını gerektirir; onun yerine Developer ID ve notarize).
- Ekran görüntüsü modu: `Deskmap --shots <dir>` gerçek arayüzü demo
  verisiyle (uydurma ekranlar, profiller, sabitlemeler ve pencereler) çizer
  ve PNG yazar; `rules.json`’a, Erişilebilirlik iznine ya da çalışan bir
  kopyaya dokunmaz (`app/Sources/Deskmap/Demo/`). Türkçe ekran görüntüleri için
  `-AppleLanguages "(tr)"` ile çalıştır.
- Dağıtım için paket üst verisi: `LSApplicationCategoryType` (productivity)
  ve `NSHumanReadableCopyright`. Görünen ad `build-app.sh` içindeki
  `DISPLAY_NAME` değişkeninden gelir; `BUILD_ROOT` derlemeyi `build/` dışında
  bir yere yönlendirebilir (oradan çalışan bir kopya varken işe yarar).
- Tek adımlık geri alma. Sabitlemeyi kaldırdıktan, bir profili sildikten,
  masaüstlerinin sırasını değiştirdikten, bir sabitlemeyi başka bir hedefe
  sürükledikten, var olan bir hedefin üstüne yeniden sabitledikten
  (“Sabitleme güncellendi”) ya da başlık parçalarını düzenledikten sonra alt
  çubukta 10 sn boyunca “*işlem* · Geri al” görünür; ⌘Z de çalışır. Geçici
  bir sabitlemeyi sürüklemek ve masaüstü sırası değişince kayan geçici
  sabitlemeler de geri alınır (kayıt, belgenin dışındaki durum için bir
  closure taşır). Kayıt, işlemden sonraki belgeyi de saklar: arada başka bir
  şey belgeyi değiştirirse (yeni bir sabitleme, bir düzen adımı, profil
  değiştirme, bir URL komutu) kayıt atılır, böylece geri alma o değişikliği
  silemez. Düzen adımları ve profil değiştirmeler kaydedilmez
  (`Models/UndoBuffer.swift`, `Store.undo()`).
- Simge düğmeleri ve anahtarlar için erişilebilirlik etiketleri, ipuçlarıyla
  aynı sözlerle: açma/kapama anahtarı, plan seçici, yeniden uygula, çık,
  raptiye düğmesi, kapatma düğmeleri, profil ekle/içe aktar, düzen hazır
  ayarları.
- Başlık parçaları sabitleme panelinde yazmadan düzenlenebilir: sabitlemeye
  uyan bir pencere açıksa başlığı parçalara bölünür, şu anki parçalar seçili
  gelir, “Tüm pencereler” seçilebilir ve uyan pencere sayısı canlı güncellenir;
  **Uygula** kaydeder. Başka bir sabitlemeyle aynı anahtarı verecek bir seçim
  turuncu bir açıklamayla reddedilir. Uyan pencere yoksa parçalar yalnız
  okunur (`TokenPicker`, `Document.setTokens`).
- Gölgede kalan sabitlemeler: bir pencereye uyan ama daha özgül bir
  sabitlemeye ya da geçici bir sabitlemeye yenilen sabitleme, hedef
  masaüstünde soluk bir çip olarak görünür; ipucu önce hangi sabitlemenin
  uyduğunu söyler (`ScreenMapView.shadows`).
- Eksik masaüstü rozeti: bir sabitlemenin hedef masaüstü bağlı ekranda yoksa
  (router son masaüstüne sıkıştırır) satırda ve çipte turuncu bir “M5→3”
  rozeti (İngilizce arayüzde “D5→3”) görünür; ipucu Mission Control’de masaüstü
  eklemeyi ya da sabitlemeyi sürüklemeyi önerir.
- Pencere öndeyken klavye kısayolları: ⌘R yeniden uygula, ⌘1 / ⌘2 plan seçici
  (Monitör bağlı / Sadece laptop), ⌘Z geri al, Esc açık alt paneli kapatır.
  İpuçları kısayolu da söyler.
- Başlarken kartı: Erişilebilirlik izni verilmişken ve etkin profilde hiç
  sabitleme ya da geçici sabitleme yokken haritanın üstünde üç adım; ilk
  sabitlemeyle kaybolur.
- Alt çubuk: SkyLight çağrıları yoksa turuncu bir “Bu macOS’ta pencereleri
  masaüstleri arasında taşımak mümkün değil; yalnız ekran ve düzen
  uygulanıyor” uyarısı (hataların ve yanıt vermeyen uygulama iletilerinin
  altında). Router’ın son işlemi 30 sn sonra solar.
- `deskmap://` URL şeması: `reapply`, `pause`, `resume`, `toggle`,
  `profile/<name>` (ya da `profile?name=<name>`), `next-profile`.
  Kestirmeler’in “URL’leri Aç” (Open URLs) eylemiyle, Raycast’le, Hammerspoon’un
  `hs.urlevent.openURL`’üyle ve terminalde `open` ile çalışır. URL’ler AppKit
  delegate’i üzerinden gelir (`application(_:open:)`); ayrıştırma saf
  `URLCommand.parse` işlevidir (`Services/URLCommands.swift`). Bilinmeyen
  komutlar ya da profiller alt çubukta hata gösterir.
- Tek kopya koruması: aynı bundle ID’li başka bir Deskmap çalışıyorsa yenisi
  router oluşturmadan kapanır; böylece iki router aynı pencereler için hiç
  çekişmez.
- macOS ayarları kartı: “Alanları otomatik olarak yeniden düzenle”, “açık
  pencerelerin olduğu bir Alan’a geç”, “Pencereleri uygulamaya göre grupla” ve
  “Ekranların ayrı Alanları var” canlı denetlenir; biri yanlışken kart
  kapatılamaz, “Masaüstü ve Dock’u aç” da doğru bölmeyi açar. Dock’taki
  “Ata: Hiçbiri” (Assign To: None) hatırlatması “Anladım” ile gizlenir
  (`setupNoticeDismissed`).
- Birim testleri (`make test`, Swift Testing): kural eşleştirme ve başlık
  bölme (Türkçe İ/ı/I/i, ß–SS ve bitişik harf çiftleri eşleşmez:
  `lowercased()` anlamı), `WindowLayout`, koordinat dönüşümü, `rules.json`
  şema geçişleri (v1/v2/v3), sabitlemeler ve profiller üzerindeki belge
  işlemleri, dışa/içe aktarma, `Routing` hedef seçimi, motor yardımcıları
  (geri çekilme kararı, taşıma bekleme süresi, harici ekran sırası, alan türü
  haritası, `Router.placement`, pencere sunucusu süzgeçleri `AX.serverWindow` /
  `AX.liveEntry`, `Router.liveWindows`, `Router.shouldResumeFromPause`,
  `ScreenService.settleDelay`), geri alma, harita mantığı ve yerelleştirme.
  122 test. CI ve `.githooks/pre-commit` bunları çalıştırır.
- Depo kökünde `VERSION` dosyası; `build-app.sh` ve `make-dist.sh` onu okur
  (`VERSION` ortam değişkeni yine önceliklidir).
- `make dist`: evrensel (arm64 + x86_64) derleme, imzalama, isteğe bağlı
  notarize ve bir `build/dist/*.zip` / `.dmg` paketi
  (`scripts/make-dist.sh`, Finder için `scripts/make-dist.command`).
  `build-app.sh` `VERSION`, `UNIVERSAL` ve `SIGN_IDENTITY` alır.
- Birleşik günlük (`Services/Log.swift`, `os.Logger`, alt sistem
  `com.deskmap.app`, kategoriler `routing`, `skylight`, `ax`, `screens`):
  açılışta SkyLight durumu ve taşıma yolu; her masaüstü taşıması, düzen ve
  taşımadan vazgeçmeler, yanıt vermeyen uygulama için geri çekilmenin
  başlangıcı ve bitişi, ekranların yatışması, uykuda duraklama ve devam etme,
  geçici sabitlemelerin süresinin dolması. Pencere başlıkları gizlidir; her
  taramada hiçbir şey kayda geçmez. İzlemek için:
  `log stream --predicate 'subsystem == "com.deskmap.app"' --level info`.
- `make concurrency-check`: `-strict-concurrency=complete` ile temiz bir
  derleme yapar ve uyarıları listeler (Swift 6 hazırlığı; paket ayarları
  değişmedi, ayrı derleme klasörü `app/.build/strict`).
- `scripts/build-and-run.command`: Finder’da çift tıkla, çalışan Deskmap’i
  kapatır, derler ve yeniden açar; çıktı `build/last-build.log`’a gider.

### Değişenler {#changed-2}

- **Uygulamanın adı artık Deskmap**: Swift modülü ve hedefi, bundle
  identifier `com.deskmap.app`, logger alt sistemi, `Deskmap.app`,
  `deskmap://` URL şeması, `~/Library/Application Support/Deskmap/` klasörü
  ve `.deskmap.json` profil dışa aktarımları.
- Mağaza ve tanıtım sayfası ekran görüntüleri:
  `swift scripts/make-store-shots.swift` gerçek çekimleri tek satırlık bir
  metinle bir fonun üstüne koyar ve iki dilde 2880×1800 ile 1280×800
  kareler yazar (`docs/store/`, üretilir, depoya girmez). Ham çekimler
  1120×1280; App Store Connect bunu kabul etmiyor.
- `app/Resources/PrivacyInfo.xcprivacy`: veri toplanmaz, izleme yok, gerekçe
  isteyen tek API (user defaults). `build-app.sh` pakete kopyalar;
  [docs/app-store-submission.md](../../appstore/submission.md) bir başvuru
  için başka neler gerektiğini listeler.
- Yeni simge: başı bir pencere olan bir harita işareti. Kodla çizilir
  (`scripts/make-icons.swift`, her boyutu ve `.icns`’i tek komutla yeniden
  üretir); 64 px’in altındaki boyutlarda başlık çubuğu ve noktaları atılır,
  o boyutta yalnız leke olurlar. Menü çubuğu şablonu aynı işaretin tek parça
  silueti, pencere içinden oyulmuş.
- Günlük iletileri, `make help`, derleme betiği çıktısı ve CI adım adları
  İngilizce. Kod yorumları Türkçe kalıyor. CI işinin adı artık “Swift build
  and tests”.
- Düzen düzenleyicisindeki kenar boşluğu etiketleri sütunu genişledi
  (24 → 42 pt), İngilizce etiketler sığsın diye.
- Yeni bir belgenin ilk profili arayüz diline göre adlandırılır (“Default” /
  “Varsayılan”); var olan profil adları kullanıcı verisidir, hiç değişmez.
- Alt panel durumu tek bir değer (`UIState.panel: BottomPanel?`: sabitleme
  taslağı, sabitleme bilgisi, geçici sabitleme, profil); böylece aynı anda
  yalnız bir panel açık olur. `RootView.swift` (894 satır) UIState /
  RootView / PinPanel / RulePanels / LayoutEditor / StatusCards / TokenPicker
  olarak bölündü; panel çerçevesinin dört kopyası tek bir
  `bottomPanelChrome()` oldu. Davranış aynı.
- Araç çubuğundaki “N sabit pencere” sayacı seçili planı sayar; “· M geçici”
  yalnız seçili plan şu anki plansa görünür (geçici sabitlemeler yalnız orada
  listelenir).
- Kural ve profil mantığı (`pin`, `unpin`, `moveDesktop`, profil değiştirme /
  kopyalama / silme, dışa/içe aktarma) `Document` üzerinde saf işlemler;
  `Store` yalnız onları çağırır, yayımlar ve kaydeder. Davranış aynı.
- Hedef seçimi tek bir yerde (`Routing.select`): router, pencere satırları ve
  harita aynı kuralı seçer (geçici sabitleme, yoksa bu planda hedefi olan en
  özgül kural). Düzen denemelerinin sayımı da `Routing`’e taşındı.
- Her taramada daha az IPC çağrısı, aynı pencere kümesi ve aynı kararlarla:
  pencere sunucusu (`CGWindowListCopyWindowInfo`) her taramada bir kez okunur
  (2. aşama listesi ve canlılık denetimi onu paylaşır); alan türleri
  `displaySpaces` sonucundan gelir (pencere başına `SLSSpaceGetType` yerine;
  bilinmeyen ID’lerde IPC’ye döner); her pencerenin alanları, çerçevesi ve
  küçültülmüş durumu bir kez okunur, anlık görüntü, yerleştirme ve
  yönlendirme bunu paylaşır (önceden yönlendirilen pencerelerde 2–3 kez).
- Tarama zamanlayıcısının 0,5 sn toleransı var (sistemin zamanlayıcıları
  birleştirmesine izin verir).
- Ekranlar ya da sistem uyurken taramalar durur (`screensDidSleep` /
  `willSleep`) ve uyandıktan hemen sonra bir kez çalışır.
- Ekran değişikliği yatışırken (2,5 sn) pencereler listelenir ama taşınmaz
  (`ScreenService.isSettling`); yatıştıktan sonra her şey yeniden yerine
  konur.
- Elle taşıma (haritada sürükleme) AX öğesini doğrudan son taramanın pid’inden
  kurar; bütün uygulamaları yeniden taramak yalnız bu başarısız olursa olur.
- Masaüstü taşıma sınırı ve bekleme süresi `Routing.maxMoveAttempts` /
  `Routing.moveRetryInterval` (saf `recordMoveAttempt`).
- Katı eşzamanlılık (`-strict-concurrency=complete`) uyarıları düzeltildi:
  16 → 0. `SkyLight` `Sendable` (saklanan bütün özellikleri `let`);
  `DropTargetPreference.defaultValue` `static let`; AX geri çekilme tablosu
  bir kilidin arkasında `nonisolated(unsafe)`; `kAXTrustedCheckOptionPrompt`
  yerine sabit bir anahtar kullanılıyor; `deinit` içinde bırakılan
  zamanlayıcılar ve gözlemci belirteçleri (Router, ScreenService,
  WindowEvents, AccessibilityPermission, Store) `nonisolated(unsafe)`; uyku
  bildirimlerinden main actor’a yalnız bildirim adı geçer. Davranış aynı.
- `Rule.split` ayırıcı desenini bir kez derler (önceden her çağrıda);
  `Rule.matches` başlık parçalarının küçük harfli bir kopyasını tutar
  (`tokens` değişince yenilenir), `Routing.select` de bir başlığı pencere
  başına en çok bir kez küçük harfe çevirir. Eşleşme kararları değişmedi:
  `lowercased()` anlamı korunuyor; `.caseInsensitive` arama kullanılmadı,
  çünkü ß/SS ve bitişik harf çiftlerini de eşleştirirdi.
- Aynı `minX` değerine sahip harici ekranlar `minY`’ye, sonra UUID’ye göre
  sıralanır. Böyle bir yerleşimde `external` / `external-2` rolleri
  güncellemeden sonra bir kez yer değiştirebilir; etkilenen sabitlemeleri bir
  kez sürüklemek bunu düzeltir, sıra ondan sonra sabit kalır.
- Ekranların yatışması artık en çok 10 sn sonra biter: değişiklikler hiç
  durmazsa (gevşek kablo, aralıksız bildirimler) 2,5 sn’lik bekleme sürekli
  yeniden başlıyor ve yönlendirme sonsuza dek kapalı kalabiliyordu. İlk
  değişiklikten 10 sn sonra yatışma zorla bitirilir (“hard cap” olarak kayda
  geçer) ve pencereler yeniden yerine konur (`ScreenService.settleDelay`).
- Çerçeve yazmaları (`AX.setFrame`) pencere öğesine 3 sn zaman aşımı verir;
  böylece yavaş ama çalışan uygulamalar (büyük belgeler, yoğun tarayıcılar)
  yine yeniden boyutlanır. Okumalar süreç genelindeki 1 sn zaman aşımını
  korur; donmuş bir uygulama `setFrame`’e varmadan geri çekilmeye alınır.
  Yazmadan sonraki doğrulama okuması değişmedi.

### Düzeltilenler {#fixed-2}

- Geçici sabitleme paneli açıkken etkin profil çipine tıklamak bir şey
  yapmıyordu (`closePanels()` oturum seçimini temizlemiyordu ve bir if-else
  zinciri profil panelini gizliyordu); tek panel değeriyle bu sorun ortadan
  kalktı. Kuralı silinen ya da profil değişince kaybolan bir sabitleme paneli
  kendiliğinden kapanır.
- Bir pencereye uyan ama daha özgül bir kurala yenilen sabitleme haritada
  hiç görünmüyordu (satır kazananı gösteriyordu, çip de gizliydi).
- “Girişte başlat” gerçek `SMAppService` durumunu okur: kayıt değişince ve
  her taramada yenilenir (Sistem Ayarları’nda kapatınca kutunun işareti
  kalkar); `.requiresApproval` durumunda turuncu bir “Onay gerekli” bağlantısı
  Giriş Öğeleri’ni açar; kayıt ekleme/silme hataları alt çubukta görünür
  (önceden `try?` bunları yutuyordu). Uygulama /Applications dışında
  çalışıyorsa ipucu hangi kopyanın kaydedileceğini söyler.
- `rules.json`’daki tek bir bozuk kural (ör. `"desktop": "x"`) bütün dosyayı
  okunamaz yapıyordu; artık yalnız o kural atlanır, alt çubukta “N kural
  okunamadı” görünür ve dosya önce `rules.json.bak`’a yedeklenir. Profil içe
  aktarma da aynı ölçüde hoşgörülü.
- Daha yeni bir Deskmap’in yazdığı `rules.json` (`version` > 3) artık daha
  eski bir sürüm tarafından üzerine yazılmıyor: dosya okunur, kaydetme
  kapatılır ve alt çubukta bir uyarı görünür.
- Router bir pencereyi, bu planda hedefi olmayan daha özgül bir kural
  yüzünden atlıyordu; artık arayüzle aynı seçimi yapar (bu planda hedefi olan
  ilk uyan kural).
- “Yeniden uygula” (ve düzen belleğini temizleyen öbür işlemler) bir tarama
  sırasında basılınca etkisiz kalıyordu.
- Masaüstü taşıması tutmayan bir pencere için bitmeyen 200 ms’lik döngü;
  artık 6 denemeden sonra vazgeçer, pencere yerine varınca sayaç sıfırlanır.
- Hedef ekranda tam ekran bir uygulama görünürken pencereler artık tam ekran
  alanına “sektirilmiyor”.
- Bekleyen (400 ms gecikmeli) bir kayıt çıkışta yazılır.
- Okunamayan bir `rules.json`, üzerine yazılmadan önce `rules.json.bak`’a
  yedeklenir.
- Kapanan pencerelerin düzen ve deneme kayıtları her taramada ayıklanır
  (bellek uzun oturumlarda artık büyümüyor).
- Monitör takılıp çıkarıldıktan sonra plan seçici gerçek planı izler; Mission
  Control’de eklenen ya da silinen masaüstleri haritada hemen görünür.
- Erişilebilirlik’e yanıt vermeyen (donmuş) bir uygulama giderek uzayan
  sürelerle (2–30 sn) atlanır ve alt çubukta “X yanıt vermiyor” görünür;
  böylece tek bir uygulama bütün taramayı tıkayamaz.
- Bozuk bir dosyada etkin profil bulunamazsa üretilen varsayılan profil
  benzersiz bir ad alır (“Varsayılan (2)”).
- “Sektirme” kaldırıldı: gizli bir masaüstündeki sabit pencere, düzenini almak
  için artık şu anki masaüstünün içinden geçirilmiyor (şu anki masaüstünde
  yabancı bir pencere yanıp sönüyordu, Dock’tan uygulamaya geçmek de yanlış
  Alan’a gidiyordu). Düzen o masaüstüne ilk gidişinde uygulanır.
- Yanıt vermeyen uygulama için geri çekilme yanlış tetikleniyordu: çok
  pencereli ama yanıt veren uygulamalar (VS Code, Chrome ve öbür Electron
  uygulamaları ile tarayıcılar) toplam AX süreleri 0,7 sn’yi geçince
  atlanıyordu. Ölçüt artık tek bir AX çağrısının ≥ 0,5 sn sürmesi (donmuş bir
  uygulama ilk çağrısında 1 sn’lik zaman aşımına takılır), güvenlik ağı olarak
  da toplamın ≥ 4 sn olması. Süreç genelindeki AX zaman aşımı açılışta 1 sn’ye
  ayarlanır; böylece `kAXWindows`’tan gelen pencere öğeleri artık ~6 sn’lik
  varsayılanı kullanmıyor.
- Pencere olay gözlemcisi ana iş parçacığını kilitleyebiliyordu: uygulama
  öğesine 1 sn zaman aşımı verilir, açılışını bitirmemiş uygulamalar atlanır,
  kaydı başarısız olan bir uygulama da giderek uzayan aralıklarla (2 → 30 sn)
  yeniden denenir; uygulama açılınca, öne gelince ya da kapanınca bekleme
  temizlenir.
- Masaüstü taşımasından vazgeçmek kalıcıydı (6 denemeden sonra “Yeniden
  uygula”ya kadar bir daha denenmiyordu); artık son denemeden 60 sn sonra yeni
  bir tur başlar.
- Pencere sunucusu boş liste döndürünce (geçici bir aksaklık) geçici
  sabitlemeler atılmıyor.
- Harici ekran rol sırası (`external`, `external-2`) aynı `minX` için
  belirsizdi; artık (minX, minY, UUID) ile belirlenir.
- Geri alma arada yapılan değişiklikleri siliyordu: kayıt bütün belgeyi geri
  getirdiği için 10 sn içindeki kaydedilmemiş işlemler (yeni bir sabitleme,
  bir düzen adımı, profil değiştirme/ekleme/yeniden adlandırma/içe aktarma,
  “Anladım”, URL komutları) ⌘Z ile sessizce kayboluyordu. Kayıt yapıldıktan
  sonra belge değişirse kayıt atılır (açma/kapama anahtarı ve tanınan ekranlar
  sayılmaz).
- Masaüstü sırasını geri almak geçici sabitlemeleri yeni numaralarında
  bırakıyordu; artık ters eşlemeyle geri dönüyorlar.
- Eksik masaüstü rozeti öbür planın haritasında yanlışlıkla çıkıyordu
  (masaüstü sayıları bağlı ekranlara aittir ve router yalnız şu anki planda
  sıkıştırır); rozet yalnız harita şu anki planı gösterirken görünür.
- Profil adı ya da yüzde alanlarında ⌘Z belgeyi geri alıyordu; odak bir metin
  alanındayken metin alanının kendi geri alması çalışır.
- “Geri al” bağlantısı hata ve yanıt vermeyen uygulama iletilerinin arkasında
  kalıyordu (⌘Z de bağlı değildi); artık alt çubuğun sağında ayrı bir öğe.
  Yer darsa önce durum metni kısaltılır.
- “Pencere sunucusu boşsa sabitlemeleri atma” koruması çalışmıyordu: AX’in
  gördüğü pencereler canlı pencere listesine her zaman ekleniyordu, liste hiç
  boş kalmıyordu; geçici sabitlemeler ve düzen/deneme kayıtları
  ayıklanabiliyordu. Artık sunucu bir şey döndürmezse liste boş kalır
  (`Router.liveWindows`); AX pencereleri yalnız boş olmayan bir listeye
  eklenir.
- Uyanma bildirimi kaçarsa (ör. uyku `willSleep`’ten sonra iptal edilirse)
  taramalar sonsuza dek duraklatılmış kalabiliyordu. Zamanlayıcı artık her
  turda denetler: ana ekran uyanıksa ve duraklama 5 sn’den eskiyse tarama
  sürer (“timer” gerekçesiyle kayda geçer). Uykuya geçerken bildirim
  sırasıyla yarışmaz.
- Süreç genelindeki 1 sn’lik AX zaman aşımı `WindowEvents` oluşturulduktan
  sonra ayarlanıyordu; bu yüzden ilk gözlemci kayıt turu pencere öğelerini
  ~6 sn’lik varsayılanla sorguluyordu. Artık ilk iş bu ayarlanıyor.

## [0.2.0] — 2026-09-02

Sadelik için baştan yazım: tek uygulama, görsel bir arayüz.

### Değişenler {#changed-3}

- Hammerspoon motoru kaldırıldı. Pencereler Erişilebilirlik API’si üzerinden
  okunup taşınır; Alanlar da doğrudan uygulamanın içinde SkyLight’ın özel
  çağrılarıyla (Hammerspoon’un ve yabai’nin kullandıklarının aynısı) ele
  alınır. macOS 12.7 ile 26.x arasındaki farklar sürüme göre karşılanır.
- Kural düzenleyicisi, ayarlar ve ekran sekmeleri yerine tek bir ekran
  haritası. Ekranlar ve masaüstleri kutu olarak çizilir, kurallar çip olarak
  sürüklenir. Düzen, bir çipe tıklayarak görsel olarak seçilir.
- Kural eklemek: açık pencereler listesinden seç, sonra başlığın parçalarına
  tıklayarak işaretle. Metin girişi yok.
- Ayarlar kaldırıldı: gecikmeler, günlük düzeyi, sabitleme, bildirimler,
  izleme modu. Yalnız açma/kapama anahtarı ve “Girişte başlat” kaldı.
- `rules.json` şeması v2 (`appName`, `bundleID`, `tokens`, `docked`,
  `undocked`). v1 dosyaları kendiliğinden okunur.
- Ekranlar UUID yerine rolle tanınır: `builtin`, `external`, `external-2`, …

### Kaldırılanlar {#removed-1}

- `engine/`, `install.sh`, `uninstall.sh`, `check.sh`, Lua testleri,
  `config/`, `docs/`.

## [0.1.2] — 2026-09-02

### Eklenenler {#added-4}

- Motor kendi kaynak klasörünü izler; bir `.lua` dosyası değişince
  Hammerspoon kendini yeniden yükler.

## [0.1.1] — 2026-09-02

### Düzeltilenler {#fixed-3}

- `hs.urlevent` geri çağrısı, pencere süzgecinin kilitlenmesi, yer tutucu
  ekran UUID’leri.

### Eklenenler {#added-5}

- Masaüstüne sabitleme, UUID normalleştirme, tanınan ekranlar listesinin onarımı.

## [0.1.0] — 2026-09-02

İlk sürüm: Hammerspoon motoru + SwiftUI kural düzenleyicisi.
