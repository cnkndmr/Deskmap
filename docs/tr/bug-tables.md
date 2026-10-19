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

`gece/1910-deskmap-d` dalında yukarıdaki hata testleri `DisplayRoles` üzerinden
yeniden yazıldı (A′ tablosu): `virtualLeftOfMonitorStealsExternalRole` →
`virtualLeftOfMonitorDoesNotStealExternalRole`, `roleSwapMigratesWholeLayoutWithoutConsent` →
`automaticRoleChangeIsHeldUntilConfirmed` + `menuChoiceIsConfirmedAndApplied`,
`loneVirtualDisplayTakesMonitorPlan` → `loneUnknownDisplayDoesNotTakeMonitorPlan`.
`PrimaryExternalBugTests`'te `withKnownIssue` kalmadı.

## A′. Birleşik dalda ana harici monitör (`gece/1910-deskmap-d`)

Birleşik dal Faz 1'in tek `primaryExternalUUID`'si yerine ikinci monitör
modelini (`DisplayRoles`: roller ekran UUID'siyle korunur) alıyor. Roller
artık konumla kaymıyor, ama A tablosunun iki hücresi orada açık kaldı:
**A3** (Deskmap'in kendiliğinden yaptığı rol değişimi `PlanApply`'ın bütün
`external` düzenini öbür ekrana taşımasına hâlâ izin veriyordu; onay yalnız
karttan seçilen takası kapsıyordu) ve **A4** (Deskmap'in hatırlamadığı tek ekran
`external` rolünü ve planını alıyordu, aksini söyleyecek menü de yoktu). Bu
dal ikisini tek kuralla kapatıyor:

> **Bir rolü o rolde hatırlanmayan bir ekran tutuyorsa rol bekler.**
> Ekran bağlı değilmiş gibi davranılır: ona plan uygulanmaz (ne oraya ne
> oradan taşıma, orada masaüstü açma ya da silme yok, artık temizliği yok),
> kural ya da pin ona yönlendirilmez (yedek olarak da). Kartında *yeni monitör
> · düzen bekliyor* yazar, başlık menüsü *Ekstra monitör / 2. monitör … olarak
> kullan* sunar; onaydan sonra seçim hatırlanır ve plan hemen uygulanır.
> `deskmap screen-role EKRAN ROL` aynısını yapar.

İlk monitör hiç öğrenilmeden önce (yeni kurulum, `displayRoles`'suz sürümden
yükseltme ya da Ayarlar › *Unut* sonrası) hiçbir şey beklemez: roller eskisi
gibi soldan sağa sıradan gelir ve öğrenilir. Bu ilk adımın geride kaldığını
`displayRoles.learnedOnce` kaydeder (eski dosyalarda: bir şey hatırlanıyorsa
açık). Test ekranı ("Deskmap Test Display") hiç beklemez.

Testler: `PrimaryExternalBugTests`, `PrimaryExternalServiceTests`,
`DisplayRolesTests`, `scripts/clitest` (`ScreenRoleTest`).

| İşlem \ Durum | Henüz öğrenilen yok | Hatırlanan monitör tek | Hatırlanan monitör + tanınmayan ekran | Hatırlanan yok, tanınmayan ekran tek | Aynı rolde iki hatırlanan, ikisi bağlı | Bir monitör unutuldu, bağlı |
| --- | --- | --- | --- | --- | --- | --- |
| Tak, ekranlar yatışır | OK: konum sırası, öğrenilir `firstConnectionIsNotHeld` | OK `virtualRightOfMonitorKeepsMonitorExternal` | OK: tanınmayan `external-2` alır, bekler `virtualLeftOfMonitorDoesNotStealExternalRole` | DÜZELTME: `external` alır, bekler, öğrenilmez `loneUnknownDisplayDoesNotTakeMonitorPlan`, `loneVirtualIsHeldUntilChosen` | DÜZELTME: eskisi `external-2`ye düşer, bekler `automaticRoleChangeIsHeldUntilConfirmed` | DÜZELTME: bekler, yeniden öğrenilmez `forgettingOneMonitorPutsItOnHold` |
| Yeniden düzenle (sanal ekran sola) | OK (ilk yatışmada öğrenildi) | — | OK `virtualLeftOfMonitorDoesNotStealExternalRole` | — | OK | — |
| Planı uygula (geçiş, *Planı şimdi uygula*) | OK `correctRolesNeedNoWork` | OK | DÜZELTME: bekleyen rol dışarıda `holdingKeepsOtherRoles` | DÜZELTME: masaüstü, taşıma, yeniden bağlama yok `loneUnknownDisplayDoesNotTakeMonitorPlan` | DÜZELTME: monitörün adlı masaüstüleri yerinde `automaticRoleChangeIsHeldUntilConfirmed` (kapı olmasa: `withoutTheGateTheWholeLayoutWouldMove`) | DÜZELTME (aynı) |
| Pinler ve kurallar | OK | OK | DÜZELTME: bekleyen role kural ya da yedek yok `heldRoleIsNotAFallbackTarget` | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) |
| Artık temizliği | OK | OK | DÜZELTME `cleanupLeavesHeldDisplayAlone` | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) |
| Kart menüsü: *… olarak kullan* (onay) | — | — | DÜZELTME: hatırlanır, plan uygulanır `loneVirtualIsHeldUntilChosen` | DÜZELTME: *Ekstra monitör* `loneUnknownDisplayConfirmedAsExtraMonitor` ya da *2. monitör* (Ekstra monitör boş kalır) `loneUnknownDisplayCanBecomeMonitor2` | DÜZELTME `menuChoiceIsConfirmedAndApplied` | DÜZELTME (aynı) |
| Kart menüsü: öbür monitörle takas (onay) | — | — | OK `choosingTheOtherMonitorSwapsRoles` | — | OK | — |
| Kart menüsü: *Bu monitörü unut* | — | DÜZELTME: yeni; rol bekler `forgetOneHoldsForgetAllStartsOver` | DÜZELTME (aynı) | — | DÜZELTME (aynı) | — |
| Ayarlar › *Unut* (hepsi) | OK | OK: baştan, yeniden öğrenilir `forgetOneHoldsForgetAllStartsOver` | OK | OK | OK | OK |
| `deskmap screen-role EKRAN ROL` / `EKRAN --forget` / `--forget` | OK | OK | DÜZELTME: menüyle aynı `ScreenRoleTest`, `forgetOneURLParses` | DÜZELTME: hatırlanan monitör yokken `ROL` bağlı sayıyı aşabilir (`choosableRoles`) | DÜZELTME | DÜZELTME |
| `deskmap screens` | OK | OK *role kept* | DÜZELTME: *role on hold* ve onay komutu `test_held_role_is_shown_with_how_to_confirm` | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) |
| Eski dosya (`learnedOnce` yok) | OK `olderFileWithoutFlag` | OK | OK | OK | OK | OK |

Burada test edilmeyen (gerçek ekran gerekir): onay pencerelerinin ekrandaki
metni, onaydan sonra `applyPlanNow`'un bir kez çalışması (takasın yatışma
geçişiyle iki kez değil) ve geniş monitörün gerçekten sökülüp takılması.

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
| Kural silindi | OK `deletedRuleReleasesWindow` | OK | HATA (haritada pin kaldırma kuralı siler; B1 ile aynı) → DÜZELTME `deletedRuleLeavesWindowInPlace` | OK | OK |
| Kural yerinde düzenlendi (parçalar değişti) | DÜZELTME: bağ düşer, yeni parçalara göre seçilir `editedRuleRebindsByNewTokens` | — | DÜZELTME (aynı) | — | — |
| Pencere kapandı | OK: bağ budanır `bindingsPrunedWithWindows` | OK | OK | OK | OK |

## Kararlar (geliştirici için)

A. Ana harici monitör
1. Hatırlanmayan tek harici ekran: `external` rolünün dışında kalsın mı
   (öneri), düzeni mi alsın (bugünkü gibi)? Öneri yalnız bir monitör
   hatırlandıysa geçerli; hatırlanan yoksa davranış değişmez.
2. Hatırlanan monitörü değiştirmek bütün düzeni taşır: önce onay (öneri) mi,
   sessiz geçiş mi?
3. Kart adları: "Ekstra monitör" / "2. monitör" / "3. monitör" (öneri).

A′. Birleşik dal (`gece/1910-deskmap-d`)
1. Rolünde hatırlanmayan ekran, kartından ya da `deskmap screen-role` ile
   seçilene dek bekler (plan yok, kural yok) (öneri); düzeni hemen almaz.
2. Bu yüzden ofisteki yeni monitör Ekstra monitör düzeni oraya gitmeden önce bir
   kez sorar (*Ekstra monitör olarak kullan*); sonra hatırlanır. Uygun mu, yoksa
   başka hiçbir şey bağlı değilken tek ekran sormadan `external` mı alsın (yalnız
   sanal ekranlar beklesin)? macOS güvenilir bir "sanal" işareti vermiyor.
3. Karttaki *Bu monitörü unut* tek monitörü unutur (rolü yeniden bekler);
   Ayarlar › *Unut* hepsini unutur, baştan başlar (konumdan yeniden öğrenilir).

B. Pencere kayması
1. Yapışkan bağ pencere açık kaldıkça yaşar (öneri); kesin olarak daha özgül
   bir kural pencereyi yine alabilir, daha az özgül olan asla.
2. Kaldırılan geçici pin pencereyi olduğu yerde bırakır (öneri).
3. Genel başlık (başlık = uygulama adı) için bekleme: 8 saniye (öneri); gerçek
   bir yeni oturum penceresiyle bir kez ölçülmeli.
4. Tam başlık sahibi: tek parçalı bir kuralın parçasına bütün başlığı eşit
   olan pencere açıkken, yalnız o parçayı içeren öbür pencereler kurala uymaz.
