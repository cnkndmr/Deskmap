# Hata tabloları: ana harici monitör, pencere kayması, haritada gösterme, sıralı yerler

Üç açık hata, her biri işlem × durum tablosu olarak. Her hücrede hatayı
yeniden üreten testin adı var (`app/Tests/DeskmapTests/`). `main`'de hatalı
hücreler `withKnownIssue` ile işaretli; takım yeşil kalır, her bilinen hata
test çıktısında listelenir. Bu testler gerçek pencere taşımaz: ekranlar,
masaüstüleri ve pencereler sahte. D bölümü hata değil: sıralı yerler
tasarımının işlem × durum tablosu.

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
`DisplayRolesTests`, `PlanPickerFollowTests`, `scripts/clitest` (`ScreenRoleTest`).

| İşlem \ Durum | Henüz öğrenilen yok | Hatırlanan monitör tek | Hatırlanan monitör + tanınmayan ekran | Hatırlanan yok, tanınmayan ekran tek | Aynı rolde iki hatırlanan, ikisi bağlı | Bir monitör unutuldu, bağlı |
| --- | --- | --- | --- | --- | --- | --- |
| Tak, ekranlar yatışır | OK: konum sırası, öğrenilir `firstConnectionIsNotHeld` | OK `virtualRightOfMonitorKeepsMonitorExternal` | OK: tanınmayan `external-2` alır, bekler `virtualLeftOfMonitorDoesNotStealExternalRole` | DÜZELTME: `external` alır, bekler, öğrenilmez `loneUnknownDisplayDoesNotTakeMonitorPlan`, `loneVirtualIsHeldUntilChosen` | DÜZELTME: eskisi `external-2`ye düşer, bekler `automaticRoleChangeIsHeldUntilConfirmed` | DÜZELTME: bekler, yeniden öğrenilmez `forgettingOneMonitorPutsItOnHold` |
| Plan seçici değişimi izler (tek ekran değişimi, tek `$screens` yayını) | HATA: seçici bir adım geride kalıyordu (`@Published` henüz willSet'teyken `screens.mode` okunuyordu) → DÜZELTME: yayınlanan listeyi izler `pickerFollowsPublishedScreens`, `publishIsWillSet` | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) | DÜZELTME (aynı) |
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
| Açılış / ilk tarama | OK `mostSpecificRuleTakesOver` | HATA `newWindowWithTransientTitleWaits` → DÜZELTME `transientTitleIsHeld` | OK | HATA `forkWindowDoesNotShareOriginalRule` → DÜZELTME `exactOwnerKeepsRule` | OK `sessionPinBeatsEveryRule` |
| Başlık uzar, parçayı içerir | HATA `mainWindowTokenSkipsLongerTitlesWhileOwned` → DÜZELTME `exactOwnerKeepsRule` | — | — | — | — |
| Başlık başka bir şeye döner | HATA `titleChangeKeepsWindowOnItsRule` → DÜZELTME `bindingSurvivesTitleChange` | DÜZELTME: henüz bağlı değil, yeni adıyla yönlenir | HATA `renamedSessionKeepsItsRule` → DÜZELTME `bindingSurvivesTitleChange` | — | — |
| Pin kaldırıldı | — | — | — | — | HATA `unpinLeavesWindowInPlace` → DÜZELTME `unpinnedWindowStays` |
| Daha özgül bir kural uymaya başlar | OK `moreSpecificRuleTakesOver` | OK | OK (yükseltme) `moreSpecificRuleUpgradesBinding` | OK | OK |
| Kural silindi | OK `deletedRuleReleasesWindow` | OK | HATA (haritada pin kaldırma kuralı siler; B1 ile aynı) → DÜZELTME `deletedRuleLeavesWindowInPlace` | OK | OK |
| Kural yerinde düzenlendi (parçalar değişti) | DÜZELTME: bağ düşer, yeni parçalara göre seçilir `editedRuleRebindsByNewTokens` | — | DÜZELTME (aynı) | — | — |
| Pencere kapandı | OK: bağ budanır `bindingsPrunedWithWindows` | OK | OK | OK | OK |

`gece/1910-deskmap-e`'de her hata hücresi `WindowDriftBugTests`'te iki katmanı
birden sabitleyen tek test: durumsuz `Routing.select` (bağlamsız) kaymayı
hâlâ yeniden üretir (teşhis, `// teşhis` işaretli), gerçek Router düzeltir.
Gerçek Router sahte ekran ve pencerelerle koşar (`RouterHarness`,
`Router.sweepSelection`: taramanın kendi girdileri, `Router.select` ve
birleştirme; AX yok, pencere taşınmaz); `WindowDriftFixTests` ve
`RouterSelectionTests` de bunu kullanır. Yeni adlar:
`unpinFallsBackToAppWideRule` → `unpinLeavesWindowInPlace`,
`newWindowWithTransientTitleTakesMainWindowRule` → `newWindowWithTransientTitleWaits`,
`mainWindowTokenMatchesLongerTitles` → `mainWindowTokenSkipsLongerTitlesWhileOwned`,
`forkWindowSharesOriginalRule` → `forkWindowDoesNotShareOriginalRule`,
`titleChangeMovesWindowToAnotherRule` → `titleChangeKeepsWindowOnItsRule`,
`renamedSessionFallsToAppWideRule` → `renamedSessionKeepsItsRule`. Takımda
`withKnownIssue` kalmadı. Grup taşıma (`GroupMovePlan.make`) ve haritanın gölge
listesi (`ScreenMapView.shadows`) artık Router'ın bağını alıyor
(`router.context(for:)`): `groupMoveMovesBoundRule`, `shadowsFollowBinding`.

## C. Harita gösterilen pencereye kaymıyor (`ui.reveal`)

Harita açılınca öndeki pencere seçilir ve harita onun satırına kaydırılır
(`showFrontWindow` → `ui.reveal`). macOS 27.0'da (26A428) harita hiç kaymıyordu.

### Kök neden

`RootView`, `proxy.scrollTo`'yu `withAnimation(.easeInOut)` içinde çağırıyordu.
Bu macOS'ta animasyonlu `ScrollViewReader.scrollTo` hiçbir şey yapmıyor; aynı
çağrı animasyonsuz kaydırıyor. Ölçüm: `NSApplication.run` altında bağımsız bir
SwiftUI uygulaması (düz, `.default`, `.linear`, `.spring`, `.top` çapası ve
ertelenmiş çağrı: yalnız düz çağrı kaydırıyor), `--shots` kipi ve aşağıdaki
test. Neden olmayanlar: çapa kimlikleri (`WindowAnchor` liste satırına da ızgara
kutusuna da bağlı), tembel yığınlar (haritada yok), okuyucu (haritanın kendi
`ScrollViewReader`'ı), zamanlama (ertelenen çağrı çalışıyor). Eski macOS
sürümleri (13–26) ölçülmedi. `--shots` kalabalık kareleri de bu çağrıya
dayanıyordu; `Shots.swift`'teki `scrollMap(ui:toBottom:)` geçici çözümü artık
yok.

### Tablo

| İşlem \ Durum | Harita listesi, satır var | Görsel ızgara, kutu var | Pencere "+N daha" arkasında |
| --- | --- | --- | --- |
| Haritayı öndeki pencerede aç | HATA `animatedScrollToDoesNotMove` → DÜZELTME `revealScrollsToWindowRow` | HATA (aynı çağrı) → DÜZELTME (aynı) | ölçülmedi: çapa yok, harita yerinde kalmalı |
| Shots kareleri `g01b`, `g01c`, `g02`, `g03`, `d4` | HATA: kareler en üstte kalıyordu → DÜZELTME: kareler pencereye kayıyor | HATA → DÜZELTME | — |

`animatedScrollToDoesNotMove` eski çağrıyı `withKnownIssue` altında tutar
(aralıklı: başka bir macOS sürümü kaydırabilir). Düzeltme
(`gece/1910-deskmap-i18n`) animasyonsuz kaydırır (`MapReveal.scroll`): harita
satıra kayarak değil, atlayarak gider. Izgara kutusu kimliğini `.offset`'ten
sonra taşıdığı için kaydırma hedefi kutunun kendisi değil masaüstü kartının sol
üstü; kart yine görünür alanda kalıyor, dokunulmadı.

## D. Birden çok monitörde sıralı yerler

Hata değil: sıralı yerlerin (`Rule.docked` + `dockedNext`,
`Routing.resolvePlace`) tasarım tablosu. Her satır
`app/Tests/DeskmapTests/DockedPlacesTests.swift`’te (`d1_1_…` = D1.1 satırı) ya da
`scripts/clitest/test_deskmap.py`’de (`DockedListTests`) bir test.

Örnek masa: rol sırası 1. Dell, 2. LG, 3. Samsung (Samsung’da 2 masaüstü);
dahili ekran hep var. Safari: `LG · 1`, `Dell · 2`, laptop `Laptop · 1`. Mail:
`Dell · 3`, laptop `Laptop · 2`. Notlar: `Samsung · 2`, laptop yeri yok. Müzik:
monitör yeri yok, laptop `Laptop · 3`. "Dokunulmaz": Deskmap pencereyi taşımaz.

| Satır | Durum | İşlem | Beklenen |
| --- | --- | --- | --- |
| D1.1 | yalnız laptop | — | Safari Laptop · 1, Mail Laptop · 2, Müzik Laptop · 3, Notlar dokunulmaz |
| D1.2 | yalnız laptop | Dell’i tak | Safari Dell · 2, Mail Dell · 3, Notlar Dell · 2 (yedek), Müzik dokunulmaz |
| D1.3 | Dell | LG’yi tak | Safari LG · 1, Mail Dell · 3, Notlar Dell · 2 |
| D1.4 | Dell + LG | Samsung’u tak | Notlar Samsung · 2, ötekiler yerinde |
| D1.5 | üçü | LG’yi çıkar | Safari Dell · 2’ye döner |
| D1.6 | Dell + LG | Dell’i çıkar | Safari LG · 1, Mail LG · 3 (yedek), Notlar LG · 2 |
| D1.7 | LG | Dell’i geri tak | Mail Dell · 3’e döner, Safari LG · 1’de kalır |
| D1.8 | Dell + LG | hepsini çıkar | laptop yerleri; Notlar dokunulmaz |
| D1.9 | Dell + LG | Sistem Ayarları’nda LG’yi Dell’in soluna al | hiçbir şey taşınmaz (roller UUID’ye bağlı) |
| D1.10 | yalnız Samsung | — | Mail Samsung · 2 (3. masaüstü yok → son), Safari Samsung · 1 (ilk yerin numarası) |
| D2.1 | Dell | tanınmayan BenQ’yu tak | BenQ onay bekler, ona bir şey gitmez |
| D2.2 | D2.1 sonrası | BenQ’yu sıranın sonuna ekle (4. monitör) | kimse taşınmaz; BenQ yedek sırasında |
| D2.3 | D2.1 sonrası | BenQ LG’nin yerine geçer | Safari BenQ · 1 (LG’nin düzeni) |
| D2.4 | yalnız BenQ (onay bekliyor) | — | hiçbir şey taşınmaz, laptop yerleri kullanılmaz |
| D3.1 | Dell + LG | Dell kartında LG’yi seç | roller ve düzenler yer değiştirir: Mail LG · 3, Safari Dell · 1; sabitleme kaybolmaz |
| D3.2 | D3.1 sonrası | geri değiştir | önceki gibi |
| D3.3 | Dell | LG kartında (bağlı değil) Samsung’u seç | sıra Dell, Samsung, LG; Samsung takılınca Safari Samsung · 1 |
| D3.4 | — | kart menüsü | yalnız Deskmap’in gördüğü monitörler (harita turu, burada test yok) |
| D3.5 | D3.1 sonrası | Dell’i çıkar | Safari LG · 2, Mail LG · 3 |
| D4.1 | Dell + LG | Safari’yi LG · 2’ye bırak | `LG · 2`, `Dell · 2` (aynı monitör: değişir) |
| D4.2 | Dell + LG | Safari’yi Dell · 3’e bırak | `Dell · 3`, `LG · 1` (bağlı ilk yerin, LG · 1’in önüne; Dell’deki eski yer gider) |
| D4.3 | Dell | Safari’yi Samsung · 1’e bırak (bağlı değil) | `Samsung · 1`, `LG · 1`, `Dell · 2`; Safari Dell · 2’de kalır |
| D4.4 | Dell | `Dell · 2`’de ↑ | `Dell · 2`, `LG · 1` |
| D4.5 | Dell | `Dell · 2`’de × | `LG · 1` → yedek Dell · 1 |
| D4.6 | Dell | Mail’in tek yerinde × | boş liste, Mail dokunulmaz |
| D4.7 | yalnız laptop | Müzik’i Laptop · 2’ye bırak | laptop yeri değişir, monitör listesi yok |
| D4.8 | Dell | Müzik’i Dell · 1’e bırak | `Dell · 1`; laptop yeri Laptop · 3 kalır |
| D4.9 | Dell | Safari’yi Dell · 3’e bırak | `LG · 1`, `Dell · 3` (bağlı monitörün yeri bağlı ilk yerin hemen önüne girer: LG’nin önüne geçmez); LG takılınca Safari LG · 1 |
| D4.10 | Dell, Safari’nin yalnız `LG · 1` yeri var (yedekte) | Safari’yi Dell · 3’e bırak | `LG · 1`, `Dell · 3` (bağlı yer yok: sona eklenir) |
| D5.1 | Dell + LG | ilk yer LG’deki "Okuma" masaüstü | Safari "Okuma"ya gider |
| D5.2 | D5.1, "Okuma" Dell’e taşındı | — | Safari onu Dell’e izler |
| D5.3 | D5.1 | LG’yi çıkar | sıradaki yer, Dell · 2; yalnız yeri bilinmeyen bir ad varsa pencere tutulur |
| D5.4 | Dell + LG | profil değiştir | her profil kendi listesini tutar |
| D5.5 | Dell + LG | LG’yi unut | LG onay bekler; yerleri silinmez, atlanır: Safari Dell · 2 |
| D5.6 | D5.5 sonrası | LG’yi yeniden onayla | Safari LG · 1 |
| D5.7 | — | profili çoğalt | aynı sıra, yeni kural kimlikleri |
| D6.1 | Safari, iki yer | kaydet | `docked` = LG · 1, `dockedNext` = [Dell · 2] |
| D6.2 | 0.5.0 dosyası | aç | tek yerli listeler, aynı davranış |
| D6.3 | D6.1 dosyası | eski sürümle aç | yalnız `docked`’ı okur |
| D6.4 | eski sürüm D6.1’i kaydetti | aç | `dockedNext` düşmüş: tek yer |
| D6.5 | yedek / gidiş dönüş | — | listeler ve roller korunur |
| D7.1 | düzen dosyası `docked: [external-2/1, external/2]` | `deskmap apply` | iki yerli liste |
| D7.2 | düzen dosyası `docked: external/2` | `deskmap apply` | tek yer (eskisi gibi) |
| D7.3 | — | `deskmap dump` / `rules` | liste sırasıyla |
| D7.4 | — | `status.json` | pencerede `place`: `"1"`, `"2"` …, `"fallback"` ya da `"untouched"` |

Ayrıca: masaüstü silmek o ekrandaki her yeri kaydırır; silinen ikinci yer
sırasıyla hayalet masaüstüne gider ve geri gelince yine ikinci yer olur; ilk
yerin masaüstü silinince sıradaki yer ilk olur.

## E. Mission Control'de başka ekrana sürüklenen masaüstü

Hata değil: böyle bir masaüstünü geri almanın tasarım tablosu
(`Services/DesktopRevert.swift`, `Router.handleCrossings` / `runReverts`).
Saf satırlar `app/Tests/DeskmapTests/MissionControlRevertTests.swift`’te
(`e1_1_…` = E1.1 satırı); *elle* işaretli satırlar gerçek bir Mission Control
sürüklemesi ister.

macOS’ta bir Alan’ı SIP’siz başka ekrana taşıyan çağrı yok; geri alma bir
plandır: eski ekranın sonuna masaüstü ekle (Mission Control **+**), eski sıra ve
sonrasının içeriğini birer kaydır, sürüklenen masaüstünün pencerelerini eski
sırasına taşı, sürüklenen masaüstü boşsa sil. Adlar içerikle gider (R5); sayı
pinleri ve geçici pinler değişmez (Mission Control sürüklemesi de onları
kaydırmadı); izlemenin (P3) taşıdığı plan girdisi geri döner.

Örnek masa: Dell ve LG; LG’de "Okuma" (LG · 1, adlı), LG · 2, LG · 3. Safari
"Okuma"ya, Notlar `LG · 2`’ye, Mail `Dell · 3`’e sabit. Sürükleme: "Okuma"
Dell · 2’ye.

| Satır | Durum | İşlem | Beklenen | Test |
| --- | --- | --- | --- | --- |
| E1.1 | Dell + LG, kararlı | "Okuma"yı Dell · 2’ye sürükle | 1,5 sn arayla iki kez görülür, ekran kümesi aynı, Alan rol değiştirmiş: geri alınır (**Geri al** ayarı, varsayılan) | `e1_1_crossingDetected`, `e1_1_revertsByDefault`; *elle* |
| E1.2 | E1.1, Mission Control hâlâ açık | — | kapanması beklenir (açıkken açmak onu kapatırdı) | *elle* |
| E1.3 | Dell + LG | bir oturumda iki masaüstü sürükle | ikisi de geri alınır, tek kart | `e1_3_twoCrossingsInOneSession` |
| E1.4 | Dell + LG | birini sürükle, başkasını sil | silme eskisi gibi (hayalet satır); sürükleme geri alınır | `e1_4_deletionIsNotACrossing` |
| E1.6 | Deskmap kapalıyken sürüklendi | aç | kendiliğinden geri alınmaz: **Geri al** düğmeli kart | `e1_6_catchUpAsks` |
| E1.7 | yeniden başlatmadan sonra | aç | kanıt yok (R4): hiçbir şey | (yeniden başlatma kolu, değişmedi) |
| E1.8 | laptop + Dell | laptop masaüstünü Dell’e sürükle | aynı kural | `e1_8_builtinCrossing` |
| E2.1 | E1.1 | geri alma | LG · 1 yeni bir masaüstü, adı "Okuma", içinde Safari; LG’de 3, Dell’de 3 masaüstü; Notlar ve Mail yerinde | `e2_1_planShiftsAndRemoves`, `e2_1_executesRevert` |
| E2.2 | son masaüstü sürüklendi | geri alma | kaydırma yok | `e2_2_lastDesktopNoShift` |
| E2.3 | ortadaki masaüstü sürüklendi | geri alma | o sıra ve sonrası birer kayar; öncekiler yerinde | `e2_3_middleDesktopShiftsOnlyLater` |
| E2.4 | — | tam ekran Alan’ı sürükle | dokunulmaz (tam ekran Alanlar masaüstü listesinde yok) | (yapı gereği) |
| E2.5 | "Okuma"da "All Desktops" penceresi | geri alma | taşınmaz, silmeyi engellemez | `e2_5_allDesktopsWindowIgnored` |
| E2.6 | bir pencere sürüklenen masaüstünden çıkamadı | geri alma | o masaüstü silinmez; kart söyler | `e2_6_windowLeftKeepsDesktop` |
| E2.7 | masaüstü eklenemedi (ya da sona gelmedi) | geri alma | hiçbir şey değişmez; kart "geri alınamadı" | `e2_7_addFailsChangesNothing`, `e2_7_addNotAtEndMovesNothing` |
| E2.8 | masaüstü taşıma kapalı (macOS 15.x, 26.0–26.3, azaltılmış mod) | sürükle | hiçbir şey yapılmaz; kart taşımanın kapalı olduğunu söyler | `e2_8_movesOffShowsCard` |
| E2.9 | sürükleme ile geri almanın sonu arası | — | yönlendirme bekler (sayı pinli pencereler iki kez taşınmaz) | *elle* |
| E2.10 | kesildi (ekran değişti) | — | adım sınırında durur; hiçbir şey silinmez | `e2_10_abortKeepsSource` |
| E3.1 | Dell + LG | LG’yi çıkar | ekran kümesi değişti: geçiş, geri alma yok | `e3_1_vanishedRoleIsNotACrossing` |
| E3.4 | uykudan uyandı | — | uyanmadan sonra 60 sn geri alma yok | `e3_4_recentWakeLeaves` |
| E3.5 | ekran yerleşimi değişti | — | ekran bildiriminden sonra 15 sn geri alma yok | `e3_5_recentScreenChangeLeaves`; *elle* |
| E3.7 | onay bekleyen monitör | ona ya da ondan sürükle | izlenir, geri alınmaz | `e3_7_heldRoleLeaves` |
| E4.2 | — | Deskmap’te masaüstünü öbür ekrana taşı | algılanmaz (yeni Alanlar, hiçbir Alan ekran değiştirmez) | `e4_2_newSpacesAreNotCrossings` |
| E4.3 | 60 sn’den az önce geri alındı | yine sürükle | kasıtlı sayılır: izlenir | `e4_3_repeatWithinAMinuteLeaves` |
| E4.4 | E2.1 kartı | **Böyle kalsın** | aynı pin kaydırmasız yol onu sürüklendiği yere götürür | `e4_4_keepIsTheReverseCrossing` |
| E5.1–E5.3 | E2.1 | — | ad yeni Alan’da; planlar sürüklemeden önceki gibi; pinler değişmez | `e5_followThenRevertRestoresPlansAndPins`, `e5_returnPlanEntryAllProfiles` |
| E5.4 | E2.3 | — | kayan masaüstülerinin adları içerikle gider | `e5_4_shiftedNamesFollowContent` |
| E6.1 | Ayarlar | **Geri al** / **Sor** / **Bırak** | Sor: **Geri al** düğmeli kart; Bırak: D5.2 (ad izler) | `e6_1_askAndLeaveSettings`, `settingCodable` |

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

C. Haritada gösterme
1. Animasyonsuz atlama (bu daldaki düzeltme) mı, yoksa macOS 27'de çalışan
   animasyonlu bir kaydırma mı aranmalı (ör. `NSClipView`'u canlandırmak)?
