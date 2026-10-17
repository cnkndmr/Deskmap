# Gizlilik

Kısacası: uygulama hiçbir şey toplamaz, hiçbir yere bir şey göndermez; içinde
ağ kodu hiç yoktur.

## Neleri okur {#what-it-reads}

İşini yapabilmek için macOS Erişilebilirlik API’si üzerinden yalnız şunları okur:

- açık pencerelerin listesi, her pencerenin ait olduğu uygulama, başlığı,
  konumu ve boyutu
- her pencerenin hangi ekranda ve hangi masaüstünde olduğu (pencere sunucusundan)

Hepsi bu. Pencerelerin *içeriğini*, belgelerini, tuş vuruşlarını, panoyu ya da
seninle ilgili herhangi bir şeyi okumaz.

## Bunlar nereye gider {#where-that-goes}

Hiçbir yere. Uygulamada ağ kodu yok: `URLSession` yok, soket yok, analiz SDK’sı
yok, çökme raporlayıcısı yok, güncelleme denetimi yok. Kendin doğrulayabilirsin:

```sh
grep -rn 'URLSession\|import Network' app/Sources     # eşleşme yok
```

Yazdığı her şey Mac’inde, kendi Application Support klasöründe kalır:

| Dosya | İçerik |
|---|---|
| `~/Library/Application Support/Deskmap/rules.json` | sabitlemelerin, profillerin ve tanınan ekranların |
| `~/Library/Application Support/Deskmap/session-pins.json` | geçici sabitlemeler (pencere ve süreç kimlikleri) |
| `~/Library/Application Support/Deskmap/desktop-state.json` | her ekrandaki masaüstleri ve pencereleri (yalnız kimlikler, başlık yok) |
| `~/Library/Application Support/Deskmap/status.json` | `deskmap` komut satırı aracı için şu anki durumun anlık görüntüsü (ekranlar, pencereler, profil) |
| `~/Library/Application Support/Deskmap/Backups/` | `rules.json`’ın otomatik yedekleri (bir gün boyunca saatlik, bir hafta boyunca günlük, sonra hep haftalık) |

Hepsi okuyup düzenleyebileceğin ya da silebileceğin düz JSON dosyalarıdır.
Bunları silmek uygulamayı sıfırlar; uygulamayı silince geride başka hiçbir şey
kalmaz.

## Günlükler {#logs}

Uygulama macOS birleşik günlüğüne (alt sistem `com.deskmap.app`) seyrek
satırlar yazar: masaüstü taşımaları, vazgeçilen denemeler, yanıt vermeyen
uygulamalar, ekran değişiklikleri, uyku ve uyanma. Günlük işe yarasın diye
uygulama ve ekran adları açıkça görünür; **pencere başlıkları asla günlüğe
yazılmaz**. Bu satırlar da öteki sistem günlükleri gibi Mac’inde kalır, kimse
onları toplamaz.

## İstediği izinler {#permissions-it-asks-for}

- **Erişilebilirlik**: gerekli ve tek izin bu. Bu izin olmadan uygulama ne
  pencere başlıklarını görebilir ne de pencereleri taşıyabilir.

Ekran Kaydı, Tam Disk Erişimi, Kişiler, Takvim, Mikrofon, Kamera ya da başka
herhangi bir izin istemez. Kendini bu uygulama diye tanıtan bir uygulama
bunları istiyorsa, o bu uygulama değildir.
