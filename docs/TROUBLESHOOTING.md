# Sorun giderme

## Pencere hiç taşınmıyor

Sırayla kontrol edin:

1. **Erişilebilirlik izni** — Hammerspoon *ve* Space Router için açık mı?
   İzin verdikten sonra ilgili uygulama yeniden başlatıldı mı?
2. **Motor çalışıyor mu** — menü çubuğunda **SR** göstergesi var mı?
   `⚠︎` görünüyorsa yapılandırma yüklenememiştir.
3. **Kural eşleşiyor mu** — **SR → İzlenen pencereleri konsola yaz**.
   Başlığın altında "eşleşme yok" yazıyorsa metin tutmuyordur.
4. **Uygulama adı doğru mu** — VS Code'un adı `Code`'dur, `Visual Studio
   Code` değil. **TÜM pencereleri konsola yaz** ile doğrulayın.
5. **Yeterli Desktop var mı** — hedef numara kadar normal masaüstü
   oluşturulmuş olmalı.
6. **Pencere tam ekran mı** — tam ekran pencereler taşınmaz.

## "Ekran bağlı değil, ana ekrana düşülüyor" uyarısı

Yapılandırmadaki ekran UUID'si hiçbir bağlı ekranla eşleşmiyor. En sık
sebebi, kurulumdan gelen `REPLACE-WITH-BUILTIN-UUID` gibi yer tutucu
değerlerin hiç doldurulmamış olmasıdır.

Menü çubuğu uygulamasında **Ekranlar** sekmesini açın; uyarı kutusundaki
**Kayıtları düzelt** düğmesi kayıtları bağlı ekranlarla hizalar. Menü her
açıldığında bu düzeltme kendiliğinden de denenir.

Motor tarafında durumu görmek için: **SR → Ekran kayıtlarını doğrula**.
Kayıtlı ve bağlı ekranların UUID'lerini yan yana yazar.

UUID tutmazsa motor ekran **adına** göre eşleştirmeyi dener ve bunu
uyarı olarak bildirir; bu geçici bir kurtarmadır, UUID'yi güncelleyin.

## Masaüstü numaraları kayıyor

`desktop` değeri o ekrandaki normal masaüstlerinin sırasıdır, Mission
Control'ün global numarası değil; dahili ekrana masaüstü eklemek harici
monitörün hedeflerini bozmaz.

Aynı ekrana masaüstü eklerseniz sıra yine de kayabilir. Bunun için
`settings.pinSpaces` varsayılan olarak açıktır: kural bir kez çözülür ve
gerçek Space kimliğine sabitlenir. Hedefi bilerek değiştirmek isterseniz
kuraldaki `desktop` değerini güncelleyin — sabitleme otomatik yenilenir.
Tümünü sıfırlamak için **Ayarlar → Sabitlemeleri sıfırla** veya
**SR → Masaüstü sabitlemelerini sıfırla**.

## Yanlış Desktop'a gidiyor

**System Settings → Desktop & Dock → Mission Control → Automatically
rearrange Spaces based on most recent use** seçeneğinin kapalı olduğunu
doğrulayın. Açıkken masaüstü sırası kullanım geçmişine göre değişir.

Ayrıca tam ekran uygulama Space'leri sayıma dahil edilmez; Mission
Control'de gördüğünüz sıra ile normal masaüstü sırası farklı olabilir.

## Yanlış pencereler eşleşiyor

Başlık metni fazla genel olabilir. `Research` yerine `[TG] Research`
gibi benzersiz bir önek kullanın ve yöntem olarak `prefix` seçin.

VS Code için başlık biçimini sabitleyin:

```json
"window.title": "[WS] ${rootName}${separator}${activeEditorShort}"
```

## Pencere sürekli yer değiştiriyor

Aynı pencereye uyan iki kural olabilir. Kurallar sırayla denenir ve ilk
eşleşen kazanır; ancak iki kural farklı hedeflere işaret ediyorsa ve
başlık değişiyorsa pencere gidip gelebilir. Kural listesinde çakışan
metinleri daraltın.

## Monitör takınca hiçbir şey olmuyor

Motor, dock olaylarının yatışması için varsayılan olarak 2,5 saniye
bekler. Dock'unuz yavaşsa **Ayarlar → Monitör gecikmesi** değerini
artırın. Hemen tetiklemek için **⌃⌥⌘ G**.

## Menü çubuğu uygulaması başlıkları göremiyor

Pencere başlıkları Accessibility API üzerinden okunur. **System Settings
→ Privacy & Security → Accessibility** listesinde Space Router işaretli
olmalı ve uygulama bir kez yeniden başlatılmalıdır.

`build/` içinden çalıştırdığınız uygulamayı `/Applications` altına
taşırsanız izni yeniden vermeniz gerekir; macOS izni dosya yoluna bağlar.

## Konsolda "hs.axuielement requires accessibility" hatası

Hammerspoon'a Erişilebilirlik izni verilmemiş. İzni verdikten sonra
Hammerspoon'u **kapatıp yeniden açın**; izin yeniden başlatmadan tam
olarak etkinleşmez. Bu izin olmadan pencere taşıma sessizce çalışmaz.

## Yapılandırma yüklenemedi uyarısı

Hammerspoon Console'u açın (**SR → İzlenen pencereleri konsola yaz** da
konsolu açar). Kırmızı satırlar sebebi gösterir:

- `Yapılandırma bulunamadı` → `make install` çalıştırılmamış.
- `JSON okunamadı` → dosya elle düzenlenirken bozulmuş. Uygulamadan
  yeniden kaydedin veya `config/rules.example.json` üzerinden başlayın.
- `'X' kuralı atlandı: ...` → o kuralda eksik alan var; diğerleri çalışır.

## Motoru sıfırlamak

```bash
./scripts/uninstall.sh
./scripts/install.sh
```

`rules.json` silinmez; kurallarınız korunur.

## Her şeyi kapatmak

Menü çubuğundaki **Etkin** anahtarını kapatın. Bu `settings.enabled`
değerini `false` yapar ve motor hiçbir pencereye dokunmaz.
