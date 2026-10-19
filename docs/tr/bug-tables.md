# Hata tabloları: ana harici monitör, pencere kayması

İki açık hata, her biri işlem × durum tablosu olarak. Her hücrede hatayı
yeniden üreten testin adı var (`app/Tests/DeskmapTests/`). `main`'de hatalı
hücreler `withKnownIssue` ile işaretli; takım yeşil kalır, her bilinen hata
test çıktısında listelenir. Bu testler gerçek pencere taşımaz: ekranlar,
masaüstüleri ve pencereler sahte.

Gösterim: **OK** beklendiği gibi · **HATA** yeniden üretildi · **DÜZELTME**
öneri dalında (`gece/1910-deskmap-b-oneri`) düzeltildi, `main`'de değil.

## A. Ana harici monitör (Faz 1, `primaryExternalUUID`)

Ekim denemesindeki düzen (sistem günlüğünden, nötr adlarla): dahili ekran
(0, 0); geniş monitör ("Wide") solda ve üstte (minX −1686); sanal ekran
("Virtual") dahili ekranın sağında (minX 1710). Sanal ekran deneme sırasında
iki kez kapanıp yeniden açıldı. Faz 1 işi başka bir worktree'de commit'siz
duruyor; öneri dalı onu olduğu gibi alır ve üstüne düzeltir.

### Kök nedenler

1. **Monitör seçmek bütün düzeni taşımak demek.** Roller (`external`,
   `external-2`) her şeyi taşır: kurallar, masaüstü planları, adlar. Rol
   değişince `screens` yeniden yayınlanır, Router ekran geçişi başlatır ve
   `PlanApply` `external` planını o rolü artık tutan monitöre uygular: adlı
   her masaüstünün pencereleri taşınır, öbür monitörde masaüstü açılır. Menü
   bunu sormadan yapıyordu.
2. **Tek başına kalan harici ekran her zaman `external` olur**, hatırlanan
   monitör o olmasa da (Faz 1 bunu `main`'den aynen aldı). Sanal ekran açıkken
   geniş monitörü çıkarınca monitörün bütün düzeni sanal ekrana gider.
3. **İstenen adlar yapılmadı.** İstek: "monitör model adları görünmesin; bir
   ekstra monitör *Ekstra monitör*, öbürü *2. monitör*, seçim menüsü ikincinin
   yanında". Faz 1 kartlarda model adlarını bıraktı, menüyü iki kartta da
   gösterdi; tek harici ekranla hiçbir şey değişmedi.
4. Faz 1'in yol açmadığı: dahili ekranda 13'ten 10'a kayan masaüstü. Deneme
   sürümü kaldırıldıktan sonra (eski sürüm yeniden çalışırken) alınan saatlik
   yedekte hâlâ 13'teydi; kayma daha sonra eski sürümde oldu. Ayrı bir hata,
   bu tabloda yok.

### Tablo

| İşlem \ Durum | Tek harici | İki harici, hatırlanan yok | İki harici, hatırlanan = konumca ilk | İki harici, hatırlanan = öbürü | Hatırlanan takılı değil, öbürü tek |
| --- | --- | --- | --- | --- | --- |
| Sanal ekranı monitörün sağına tak | — | OK `virtualRightOfMonitorKeepsMonitorExternal` | OK (aynı) | HATA → DÜZELTME: seçildiği gibi kalır, `rememberedSurvivesReplug` | — |
| Sanal ekranı monitörün soluna tak | — | HATA `virtualLeftOfMonitorStealsExternalRole` → DÜZELTME `rememberedMonitorKeepsRoleWhereverOthersAre` | DÜZELTME (aynı) | DÜZELTME (aynı) | — |
| Kararlı durum, roller aynı | OK `correctRolesNeedNoWork` | OK | OK | OK | — |
| Menüden öbür monitörü seç | — | HATA `roleSwapMigratesWholeLayoutWithoutConsent` → DÜZELTME `switchNeedsConfirmation` | HATA → DÜZELTME (aynı) | HATA → DÜZELTME (aynı) | — |
| Hatırlanan monitörü çıkar | — | — | — | — | HATA `loneVirtualDisplayTakesMonitorPlan` → DÜZELTME `loneOtherDisplayDoesNotTakeRememberedRole` |
| Kart başlığı | HATA (model adı) → DÜZELTME `cardTitlesUseRoleNames` | HATA → DÜZELTME (aynı) | HATA → DÜZELTME (aynı) | HATA → DÜZELTME (aynı) | HATA → DÜZELTME (aynı) |
| Menünün görünmesi | OK gizli `pickerOnlyOnSecondCard` | HATA iki kartta → DÜZELTME (aynı) | DÜZELTME | DÜZELTME | DÜZELTME gizli |

Açık kararlar (öneri dalı): sondaki "Kararlar" bölümü.

## B. Pencere kayması (Claude pencereleri)

Seçim durumsuz: her taramada `Routing.select` her pencereyi **o anki**
başlığıyla eşler. Claude başlıkları oynar (yeni oturum penceresi "Claude"
diye açılır, adını birkaç saniye sonra alır; ana pencere açık sohbetin adını
gösterebilir; fork " (fork)" ekler) ve başlık parçaları alt dizi olarak eşleşir.

### Kök nedenler

1. **Pencere başına hafıza yok.** Bir kuralın ya da pinin yerleştirdiği
   pencere, başlık değişir değişmez ya da pin kalkar kalkmaz başka kurala düşer.
2. **Geçici başlıklar hemen yönlendiriliyor.** "Claude" başlıklı yeni oturum
   penceresi ana pencere kuralına uyar, adını almadan ana masaüstüne taşınır.
3. **Sahipsiz alt dizi eşleşmesi.** Bir pencerenin başlığından yapılmış kural,
   o başlığı içeren her başlığa da uyar ("X" ve "X (fork)", "Claude" ve
   "Claude Code notes").

### Tablo

| İşlem \ Durum | Ana pencere ("Claude") | Yeni oturum penceresi, ilk saniyeler | Kendi kuralı olan oturum penceresi | Oturum penceresinin fork'u | Geçici pinli pencere |
| --- | --- | --- | --- | --- | --- |
| Açılış / ilk tarama | OK `mostSpecificRuleTakesOver` | HATA `newWindowWithTransientTitleTakesMainWindowRule` → DÜZELTME `transientTitleIsHeld` | OK | HATA `forkWindowSharesOriginalRule` → DÜZELTME `exactOwnerKeepsRule` | OK `sessionPinBeatsEveryRule` |
| Başlık uzar, parçayı içerir | HATA `mainWindowTokenMatchesLongerTitles` → DÜZELTME `exactOwnerKeepsRule` | — | — | — | — |
| Başlık başka bir şeye döner | HATA `titleChangeMovesWindowToAnotherRule` → DÜZELTME `bindingSurvivesTitleChange` | DÜZELTME: henüz bağlı değil, yeni adıyla yönlenir | HATA `renamedSessionFallsToAppWideRule` → DÜZELTME `bindingSurvivesTitleChange` | — | — |
| Pin kaldırıldı | — | — | — | — | HATA `unpinFallsBackToAppWideRule` → DÜZELTME `unpinnedWindowStays` |
| Daha özgül bir kural uymaya başlar | OK `moreSpecificRuleTakesOver` | OK | OK (yükseltme) `moreSpecificRuleUpgradesBinding` | OK | OK |
| Kural silindi | OK `deletedRuleReleasesWindow` | OK | OK `deletedRuleDropsBinding` | OK | OK |
| Pencere kapandı | OK: bağ budanır `bindingsPrunedWithWindows` | OK | OK | OK | OK |

## Kararlar (geliştirici için)

A. Ana harici monitör
1. Hatırlanmayan tek harici ekran: `external` rolünün dışında kalsın mı
   (öneri), düzeni mi alsın (bugünkü gibi)? Öneri yalnız bir monitör
   hatırlandıysa geçerli; hatırlanan yoksa davranış değişmez.
2. Hatırlanan monitörü değiştirmek bütün düzeni taşır: önce onay (öneri) mi,
   sessiz geçiş mi?
3. Kart adları: "Ekstra monitör" / "2. monitör" / "3. monitör" (öneri).

B. Pencere kayması
1. Yapışkan bağ pencere açık kaldıkça yaşar (öneri); kesin olarak daha özgül
   bir kural pencereyi yine alabilir, daha az özgül olan asla.
2. Kaldırılan geçici pin pencereyi olduğu yerde bırakır (öneri).
3. Genel başlık (başlık = uygulama adı) için bekleme: 8 saniye (öneri); gerçek
   bir yeni oturum penceresiyle bir kez ölçülmeli.
4. Tam başlık sahibi: tek parçalı bir kuralın parçasına bütün başlığı eşit
   olan pencere açıkken, yalnız o parçayı içeren öbür pencereler kurala uymaz.
