# Release checklist

How a Deskmap version gets from `main` to a download people can install.
Written 2026-10-19 for 0.6.0 (see [release-0.6.0.md](release-0.6.0.md)); it
replaces the short list at the end of [distribution.md](distribution.md).
English first, Turkish below. Items marked **[decision]** need the maintainer's
call, not a command.

Rules that hold for every release: the version number is changed in exactly
the places listed in step 1 and nowhere else; nothing is tagged or published
until step 6 passed on a second Mac or a fresh user account; the release is not
finished until the Homebrew tap points at it (step 8).

## English

### 0. Before touching the version

- [ ] `main` contains everything that goes out: the night branches are merged,
      `git status` is clean, `git log --oneline v0.5.0..main` reads as the
      changelog does.
- [ ] `CHANGELOG.md` `[Unreleased]` and `docs/tr/CHANGELOG.md` `[Unreleased]`
      say the same things. Both currently have **two `### Added` / `###
      Eklenenler` sections** (the second holds *Automatic backups*): merge them
      into one before cutting the section, and keep Keep-a-Changelog order
      (Added, Changed, Removed, Fixed).
- [ ] `make test`, `make cli-test`, `make concurrency-check` (report only) and
      `make check` green on the release machine. CI (`.github/workflows/ci.yml`)
      green on `main`.
- [ ] `docs/bug-tables.md` has no `withKnownIssue` left that the release notes
      do not mention as a known limit. The decisions at its end (A, A′, B) are
      either taken or listed under *Known limits* in the release notes.
- [ ] **[decision]** Developer ID + notarization for this release? Apple
      Developer Program, 99 USD/year (Tanıtım Planı D3). Without it the first
      launch needs *Open Anyway* and the Accessibility permission is asked again
      after every update; with it both go away, but the permission is asked once
      more after the signature changes. The rest of this list covers both
      cases.

### 1. Bump the version (one source, four mirrors)

The number lives in **`VERSION`** (`0.5.0` → `0.6.0`). Everything that builds
reads it from there:

| Where | How it gets the number | Change by hand? |
|---|---|---|
| `VERSION` | the source | **yes** |
| `Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) | there is no checked-in plist; `scripts/build-app.sh` writes it from `VERSION` (or `VERSION=x.y.z make dist`) | no |
| `Makefile` | carries no version; `make dist` passes `VERSION` through to `scripts/make-dist.sh`, which names `build/dist/Deskmap-<version>.zip` / `.dmg` | no |
| Website `{{version}}` (download pages EN/TR, meta, asset cache keys) | `scripts/build-site.mjs` reads `VERSION` at build time | no |
| Homebrew cask `Casks/deskmap.rb` in `cnkndmr/homebrew-tap` (`version`, `sha256`) | `.github/workflows/homebrew.yml` on release publish (step 8) | only if the workflow fails |

Still edited by hand:

- [ ] `VERSION` → `0.6.0`.
- [ ] `CHANGELOG.md`: `## [Unreleased]` → `## [0.6.0] — YYYY-MM-DD`, add a fresh
      empty `## [Unreleased]` above it. Same heading in `docs/tr/CHANGELOG.md`
      (its 0.5.0 section uses the same `— YYYY-MM-DD` form).
- [ ] `README.md` line 15: the shields.io badge
      `version-0.5.0` → `version-0.6.0` (both `src` and `alt`).
- [ ] `docs/release-0.6.0.md` and `docs/tr/surum-0.6.0.md`: drop the *draft*
      banner, fill in the date. **[decision]** add them to the website docs list
      (`DOCS` in `scripts/build-site.mjs`, EN + TR twins with `alt`) or leave
      them GitHub-only; today they are not built into the site.
- [ ] Not a version, but checked each release: `LSMinimumSystemVersion` in
      `scripts/build-app.sh` (13.0) must still match the cask's
      `depends_on macos: :ventura` and the download page's "macOS 13 or later".
- [ ] Commit: `Release 0.6.0` (one line, English, no signature), as `900f1c8
      Release 0.5.0` did.

### 2. Build

- [ ] `make clean` first, so the universal build does not reuse a single-arch
      `.build`.
- [ ] Ad-hoc (today's path, 0.5.0 shipped this way):
      `FORMAT=both make dist` → `build/dist/Deskmap-0.6.0.zip` and `.dmg`,
      ad-hoc signed. The zip is what the cask downloads (`Deskmap-<version>.zip`,
      exact name), so always produce the zip even if a dmg is offered too.
- [ ] Developer ID (if decided):
      `SIGN_IDENTITY="Developer ID Application: <Name> (TEAMID)" NOTARY_PROFILE=notary FORMAT=both make dist`.
      One-time setup before the first run: certificate in the login keychain and
      `xcrun notarytool store-credentials notary --apple-id … --team-id … --password <app-specific>`
      (details in [distribution.md](distribution.md)).
- [ ] Check the script's summary: `Architectures: x86_64 arm64`, `Signature:`
      shows the identity (or *ad-hoc*). `codesign --verify --deep --strict`
      ran inside `make dist`; for a notarized build also
      `spctl -a -vv build/Deskmap.app` → *accepted, source=Notarized Developer
      ID*, and `xcrun stapler validate build/Deskmap.app`.
- [ ] The app shows its version nowhere in the UI, so check the bundle:
      `defaults read "$PWD/build/Deskmap.app/Contents/Info.plist" CFBundleShortVersionString`
      → `0.6.0`.

### 3. Sign, notarize

Covered by `make dist` (`scripts/make-dist.sh`): hardened runtime, secure
timestamp, `notarytool submit --wait`, `stapler staple`, and the same for the
dmg when `FORMAT` includes it. Things the script does not do:

- [ ] A notarization *rejected* result: read `xcrun notarytool log <id>
      --keychain-profile notary`; the usual causes are a missing hardened
      runtime entitlement or an unsigned helper. Fix, rebuild, resubmit; never
      ship a stapled-nothing app.
- [ ] Accessibility permission is tied to the signature. Moving from ad-hoc
      to Developer ID means every existing user grants it once more; say so in
      the release notes (*Upgrading*) and the GitHub release text.

### 4. Try it on a second Mac or a fresh user account

- [ ] Download the zip from a browser (so it carries the quarantine flag),
      unzip, drag to `/Applications`, open.
- [ ] **Gatekeeper first launch.** Ad-hoc: macOS says the app cannot be
      opened; System Settings › Privacy & Security › **Open Anyway** works and
      the welcome guide appears. Notarized: it opens with no dialog at all.
      Both are described on the download page; make sure the text that matches
      this release is the one shown.
- [ ] The welcome guide's step 1 opens System Settings › Accessibility; after
      turning Deskmap on, the guide notices it by itself.
- [ ] Upgrade path: a copy of a 0.5.0 `~/Library/Application Support/Deskmap`
      folder opens in 0.6.0, the schema 6 upgrade card appears,
      `Backups/pre-migration/` is written, pins still apply, **Undo upgrade**
      restores the old files.
- [ ] Plug a monitor in and out once: the plan picker follows, named desktops
      move, a *new monitor · layout on hold* card appears for a monitor Deskmap
      has not learned, *Use as Extra monitor* places the layout.
- [ ] On a macOS 15.x or 26.0–26.3 machine, if one is at hand: the desktop
      moves card is shown, **Try Anyway** turns moves on and survives a restart.
- [ ] `deskmap status`, `deskmap screens`, `deskmap check` run against the
      installed copy.

### 5. Tag

- [ ] `git tag -a v0.6.0 -m "Deskmap 0.6.0"` on the release commit, `git push
      origin main v0.6.0` (the tag must be `v<version>` exactly: `homebrew.yml`
      derives the asset name from it).
- [ ] Pushing `main` also triggers `pages.yml` (it watches `VERSION`,
      `CHANGELOG.md`, `docs/**`, `website/**`): the site now says *Version
      0.6.0* and the changelog page has the 0.6.0 section.

### 6. GitHub release

- [ ] `gh release create v0.6.0 build/dist/Deskmap-0.6.0.zip build/dist/Deskmap-0.6.0.dmg --title "Deskmap 0.6.0" --notes-file <notes>`
      where `<notes>` is the 0.6.0 changelog section plus the *Upgrading*
      paragraph of `docs/release-0.6.0.md` (first launch, Accessibility,
      schema 6, pre-migration backup). Attach the assets **before** publishing:
      the tap workflow runs on *published* and looks for
      `Deskmap-0.6.0.zip` at that moment. Draft first (`--draft`), check the
      asset list, then publish.
- [ ] After publishing: `gh release view v0.6.0` shows both assets;
      `https://github.com/cnkndmr/Deskmap/releases/latest` resolves to it
      (the download page's **Download the latest release** button points there).

### 7. Homebrew tap (`homebrew.yml`)

- [ ] Actions › *Homebrew tap* run for `v0.6.0` is green. It downloads the
      zip, computes `sha256`, sets `version` and `sha256` in `Casks/deskmap.rb`
      in `cnkndmr/homebrew-tap` and pushes `deskmap 0.6.0`. Needs the repository
      secret `HOMEBREW_TAP_TOKEN` (fine-grained, Contents read/write on the
      tap); it fails with a clear message without it.
- [ ] If the run failed or an asset was re-uploaded (new sha256): Actions ›
      Homebrew tap › **Run workflow**, tag `v0.6.0`. Manual fallback: edit the
      two lines in the local clone `~/Projects/kisisel/homebrew-tap/Casks/deskmap.rb`
      and push (`shasum -a 256 build/dist/Deskmap-0.6.0.zip`).
- [ ] The workflow never touches the rest of the cask; check by hand that
      `depends_on`, `app`, `zap trash`, `desc`, `homepage` still describe the
      app (the Deskmap `CLAUDE.md` lists when each changes).
- [ ] `brew update && brew info --cask cnkndmr/tap/deskmap` shows 0.6.0;
      `brew upgrade --cask deskmap` on the test machine installs it.
- [ ] **[decision]** The tap repository is private today (Tanıtım Planı D2);
      `brew install --cask cnkndmr/tap/deskmap` works for other people only once
      it is public.

### 8. Website download page

- [ ] `https://cnkndmr.github.io/Deskmap/download/` and `/tr/download/`:
      eyebrow and *At a glance* read *Version 0.6.0* (from `{{version}}`),
      the **Download the latest release** button lands on v0.6.0, the Homebrew
      tab's command is unchanged, the macOS note (15 and 26.0–26.3 moves off)
      still true.
- [ ] If notarized: the download page's first-launch steps (Open Anyway,
      "not notarized") and the README *Install* paragraph must be rewritten
      for this release; today both describe the ad-hoc case.
- [ ] `/changelog/` and `/tr/changelog/` show the 0.6.0 section at the top.
- [ ] **[decision]** Pages is still off (404) per Tanıtım Planı D6; the
      repository setting *Pages › Source: GitHub Actions* must be on before any
      of the above is reachable. `pages.yml` builds with `--strict`, so a broken
      doc link fails the deploy: check the Actions run.

### 9. Demo GIF in the README

- [ ] `README.md` line 42 embeds `docs/media/en/demo.gif` by relative path:
      the file (254 KB) is committed and in the release commit, so it renders
      on `github.com/cnkndmr/Deskmap`. The Turkish guide embeds
      `docs/media/tr/demo.gif`. Open both pages on GitHub after the push and
      watch the GIF loop once.
- [ ] If the UI changed after the GIF was drawn: `make demo-media` (needs
      ffmpeg; uses `--shots --scenario demo`, demo data only) and commit the
      four files in `docs/media/`.
- [ ] Release text and social posts link the GIF by its raw GitHub URL
      (`https://raw.githubusercontent.com/cnkndmr/Deskmap/main/docs/media/en/demo.gif`),
      which works once the repository is public (Tanıtım Planı D1).

### 10. Gatekeeper first launch, written down

- [ ] README *Install*, the download page (EN + TR) and the GitHub release
      text describe the same first launch as the shipped build: ad-hoc → *open
      once, Open Anyway, Grant Access, permission asked again after each
      update*; notarized → *drag, open, grant Accessibility once*.
- [ ] One sentence in the release text about the private API and that a macOS
      update may break desktop moves, as the promo texts do.

### 11. Afterwards

- [ ] Install the released build on the maintainer's own Mac with
      `make install` (`SIGN_IDENTITY` required; the old copy is set aside in
      `~/Documents/Deskmap/installed-copies/`) or from the zip, so the daily
      copy is the shipped one.
- [ ] `docs/distribution.md`: update its own short release list to point here.
- [ ] Start the next `[Unreleased]` section in both changelogs (step 1 did).
- [ ] Watch the first issues; the Tanıtım Planı's week-0 note applies: this is
      an "it is open" announcement, not the promotion wave.

## Türkçe

Bir Deskmap sürümünün `main`'den kurulabilir bir indirmeye nasıl gittiği.
19.10.2026'da 0.6.0 için yazıldı (bkz. [tr/surum-0.6.0.md](tr/surum-0.6.0.md));
[distribution.md](distribution.md) sonundaki kısa listenin yerini alır.
**[karar]** işaretli maddeler komut değil, Can'ın kararını ister.

Her sürümde geçerli kurallar: sürüm numarası yalnız 1. adımda sayılan yerlerde
değişir; 4. adım ikinci bir Mac'te ya da temiz bir kullanıcı hesabında
geçmeden hiçbir şey etiketlenmez ya da yayımlanmaz; Homebrew tap'i sürümü
göstermeden (7. adım) sürüm bitmiş sayılmaz.

### 0. Sürüme dokunmadan önce

- [ ] `main` çıkacak her şeyi içeriyor: gece dalları birleşmiş, `git status`
      temiz, `git log --oneline v0.5.0..main` değişiklik günlüğüyle örtüşüyor.
- [ ] `CHANGELOG.md` ve `docs/tr/CHANGELOG.md` `[Unreleased]` bölümleri aynı
      şeyi söylüyor. İkisinde de şu an **iki `### Added` / `### Eklenenler`
      bölümü var** (ikincisi *Otomatik yedekler*): bölümü kesmeden önce tek
      bölümde birleştir, Keep-a-Changelog sırasını koru (Added, Changed,
      Removed, Fixed).
- [ ] `make test`, `make cli-test`, `make concurrency-check` (yalnız rapor) ve
      `make check` sürüm makinesinde yeşil. CI (`.github/workflows/ci.yml`)
      `main`'de yeşil.
- [ ] `docs/bug-tables.md`'de sürüm notlarının bilinen sınır olarak anmadığı
      `withKnownIssue` kalmadı. Sonundaki kararlar (A, A′, B) ya verildi ya da
      sürüm notlarında *Bilinen sınırlar* altında.
- [ ] **[karar]** Bu sürümde Developer ID + notarization var mı? Apple
      Developer Program, yılda 99 USD (Tanıtım Planı D3). Yoksa ilk açılış
      *Yine de Aç* ister ve Erişilebilirlik izni her güncellemede yeniden
      sorulur; varsa ikisi de kalkar ama imza değiştiği için izin bir kez daha
      sorulur. Listenin kalanı iki durumu da kapsıyor.

### 1. Sürüm numarasını artır (tek kaynak, dört ayna)

Numara **`VERSION`** dosyasında yaşar (`0.5.0` → `0.6.0`). Derleyen her şey onu
oradan okur:

| Nerede | Numarayı nasıl alır | Elle değişir mi? |
|---|---|---|
| `VERSION` | kaynak | **evet** |
| `Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) | depoda plist yok; `scripts/build-app.sh` onu `VERSION`'dan yazar (ya da `VERSION=x.y.z make dist`) | hayır |
| `Makefile` | sürüm taşımaz; `make dist`, `VERSION`'ı `scripts/make-dist.sh`'e geçirir, o da `build/dist/Deskmap-<sürüm>.zip` / `.dmg` adını verir | hayır |
| Web sitesi `{{version}}` (EN/TR indirme sayfaları, meta, varlık önbellek anahtarları) | `scripts/build-site.mjs` derlerken `VERSION`'ı okur | hayır |
| Homebrew cask `Casks/deskmap.rb`, `cnkndmr/homebrew-tap` (`version`, `sha256`) | sürüm yayımlanınca `.github/workflows/homebrew.yml` (7. adım) | yalnız iş akışı bozulursa |

Hâlâ elle düzenlenenler:

- [ ] `VERSION` → `0.6.0`.
- [ ] `CHANGELOG.md`: `## [Unreleased]` → `## [0.6.0] — YYYY-MM-DD`, üstüne boş
      bir `## [Unreleased]` ekle. Aynısı `docs/tr/CHANGELOG.md`'de (0.5.0
      bölümündeki biçimle).
- [ ] `README.md` 15. satır: shields.io rozeti `version-0.5.0` →
      `version-0.6.0` (`src` ve `alt` ikisi de).
- [ ] `docs/release-0.6.0.md` ve `docs/tr/surum-0.6.0.md`: *taslak* uyarısını
      kaldır, tarihi yaz. **[karar]** web sitesinin belge listesine eklensin
      mi (`scripts/build-site.mjs` içindeki `DOCS`, EN + TR ikizi `alt` ile)
      yoksa yalnız GitHub'da mı kalsın; bugün siteye derlenmiyorlar.
- [ ] Sürüm değil ama her sürümde bakılır: `scripts/build-app.sh`'teki
      `LSMinimumSystemVersion` (13.0), cask'teki `depends_on macos: :ventura`
      ve indirme sayfasındaki "macOS 13 ve üstü" ile uyuşmalı.
- [ ] Commit: `Release 0.6.0` (tek satır, İngilizce, imza yok), `900f1c8
      Release 0.5.0` gibi.

### 2. Derle

- [ ] Önce `make clean`; evrensel derleme tek mimarili `.build`'i yeniden
      kullanmasın.
- [ ] Ad-hoc (bugünkü yol, 0.5.0 böyle çıktı): `FORMAT=both make dist` →
      `build/dist/Deskmap-0.6.0.zip` ve `.dmg`, ad-hoc imzalı. Cask zip'i
      indirir (`Deskmap-<sürüm>.zip`, tam ad); dmg verilse de zip her zaman
      üretilir.
- [ ] Developer ID (karar verildiyse):
      `SIGN_IDENTITY="Developer ID Application: <Ad> (TEAMID)" NOTARY_PROFILE=notary FORMAT=both make dist`.
      İlk koşudan önce bir kez: sertifika login keychain'de ve
      `xcrun notarytool store-credentials notary --apple-id … --team-id … --password <app-specific>`
      (ayrıntı [distribution.md](distribution.md)).
- [ ] Betiğin özetine bak: `Architectures: x86_64 arm64`, `Signature:` kimliği
      (ya da *ad-hoc*) gösteriyor. `codesign --verify --deep --strict` `make
      dist` içinde koştu; notarize derlemede ayrıca `spctl -a -vv
      build/Deskmap.app` → *accepted, source=Notarized Developer ID* ve `xcrun
      stapler validate build/Deskmap.app`.
- [ ] Uygulama sürümünü arayüzde hiçbir yerde göstermiyor; pakete bak:
      `defaults read "$PWD/build/Deskmap.app/Contents/Info.plist" CFBundleShortVersionString`
      → `0.6.0`.

### 3. İmzala, notarize et

`make dist` (`scripts/make-dist.sh`) yapar: hardened runtime, güvenli zaman
damgası, `notarytool submit --wait`, `stapler staple`; `FORMAT` dmg içeriyorsa
dmg için de aynısı. Betiğin yapmadıkları:

- [ ] Notarization *rejected* dönerse: `xcrun notarytool log <id>
      --keychain-profile notary`; olağan nedenler eksik hardened runtime
      yetkisi ya da imzasız yardımcı. Düzelt, yeniden derle, yeniden gönder;
      ticket'sız uygulama asla gönderilmez.
- [ ] Erişilebilirlik izni imzaya bağlı. Ad-hoc'tan Developer ID'ye geçmek her
      kullanıcının izni bir kez daha vermesi demek; sürüm notlarında
      (*Yükseltme*) ve GitHub release metninde söyle.

### 4. İkinci Mac'te ya da temiz kullanıcı hesabında dene

- [ ] Zip'i tarayıcıdan indir (karantina bayrağı taşısın), aç,
      `/Applications`'a sürükle, çalıştır.
- [ ] **Gatekeeper ilk açılış.** Ad-hoc: macOS uygulamanın açılamayacağını
      söyler; Sistem Ayarları › Gizlilik ve Güvenlik › **Yine de Aç** çalışır
      ve karşılama rehberi gelir. Notarize: hiç pencere çıkmadan açılır. İkisi
      de indirme sayfasında anlatılıyor; bu sürüme uyan metnin görünür olduğundan
      emin ol.
- [ ] Karşılama rehberinin 1. adımı Sistem Ayarları › Erişilebilirlik'i açar;
      Deskmap açılınca rehber bunu kendiliğinden fark eder.
- [ ] Yükseltme yolu: 0.5.0'dan kopyalanmış bir `~/Library/Application
      Support/Deskmap` klasörü 0.6.0'da açılır, şema 6 yükseltme kartı çıkar,
      `Backups/pre-migration/` yazılır, sabitlemeler yine uygulanır,
      **Yükseltmeyi geri al** eski dosyaları geri getirir.
- [ ] Monitörü bir kez tak-çıkar: plan seçici izler, adlı masaüstleri taşınır,
      Deskmap'in öğrenmediği monitörde *yeni monitör · düzen bekliyor* kartı
      çıkar, *Ekstra monitör olarak kullan* düzeni yerleştirir.
- [ ] Elde macOS 15.x ya da 26.0–26.3 makine varsa: masaüstü taşıma kartı
      görünür, **Yine de dene** taşımayı açar ve yeniden başlatmada kalır.
- [ ] `deskmap status`, `deskmap screens`, `deskmap check` kurulu kopyaya
      karşı çalışır.

### 5. Etiketle

- [ ] Sürüm commit'inde `git tag -a v0.6.0 -m "Deskmap 0.6.0"`, `git push
      origin main v0.6.0` (etiket tam olarak `v<sürüm>`: `homebrew.yml` varlık
      adını ondan türetir).
- [ ] `main` push'u `pages.yml`'i de tetikler (`VERSION`, `CHANGELOG.md`,
      `docs/**`, `website/**` izlenir): site artık *Sürüm 0.6.0* der, değişiklik
      sayfasında 0.6.0 bölümü vardır.

### 6. GitHub release

- [ ] `gh release create v0.6.0 build/dist/Deskmap-0.6.0.zip build/dist/Deskmap-0.6.0.dmg --title "Deskmap 0.6.0" --notes-file <notlar>`;
      `<notlar>` = 0.6.0 changelog bölümü + `docs/release-0.6.0.md`'nin
      *Upgrading* paragrafı (ilk açılış, Erişilebilirlik, şema 6, pre-migration
      yedeği). Varlıkları yayımlamadan **önce** ekle: tap iş akışı *published*
      anında koşar ve `Deskmap-0.6.0.zip`'i o an arar. Önce taslak (`--draft`),
      varlık listesine bak, sonra yayımla.
- [ ] Yayımladıktan sonra: `gh release view v0.6.0` iki varlığı gösterir;
      `https://github.com/cnkndmr/Deskmap/releases/latest` ona gider (indirme
      sayfasındaki **Son sürümü indir** düğmesi oraya bakar).

### 7. Homebrew tap (`homebrew.yml`)

- [ ] Actions › *Homebrew tap* koşusu `v0.6.0` için yeşil. Zip'i indirir,
      `sha256` hesaplar, `cnkndmr/homebrew-tap` içindeki `Casks/deskmap.rb`'de
      `version` ve `sha256`'yı yazar, `deskmap 0.6.0` commit'ini push'lar. Depo
      sırrı `HOMEBREW_TAP_TOKEN` gerekir (fine-grained, tap'te Contents
      read/write); yoksa açık hata verir.
- [ ] Koşu bozuldu ya da varlık yeniden yüklendiyse (yeni sha256): Actions ›
      Homebrew tap › **Run workflow**, etiket `v0.6.0`. Elle yedek yol: yerel
      klon `~/Projects/kisisel/homebrew-tap/Casks/deskmap.rb`'de iki satırı
      düzenle ve push'la (`shasum -a 256 build/dist/Deskmap-0.6.0.zip`).
- [ ] İş akışı cask'in kalanına dokunmaz; `depends_on`, `app`, `zap trash`,
      `desc`, `homepage` uygulamayı hâlâ anlatıyor mu elle bak (Deskmap
      `CLAUDE.md` her birinin ne zaman değiştiğini sayar).
- [ ] `brew update && brew info --cask cnkndmr/tap/deskmap` 0.6.0 gösterir;
      test makinesinde `brew upgrade --cask deskmap` kurar.
- [ ] **[karar]** Tap deposu bugün private (Tanıtım Planı D2); `brew install
      --cask cnkndmr/tap/deskmap` başkaları için ancak public olunca çalışır.

### 8. Web sitesi indirme sayfası

- [ ] `https://cnkndmr.github.io/Deskmap/download/` ve `/tr/download/`: üst
      yazı ve *Bir bakışta* *Sürüm 0.6.0* der (`{{version}}`), **Son sürümü
      indir** v0.6.0'a iner, Homebrew sekmesindeki komut değişmedi, macOS notu
      (15 ve 26.0–26.3'te taşıma kapalı) hâlâ doğru.
- [ ] Notarize edildiyse: indirme sayfasındaki ilk açılış adımları (Yine de Aç,
      "notarize değil") ve README *Install* paragrafı bu sürüm için yeniden
      yazılmalı; bugün ikisi de ad-hoc durumu anlatıyor.
- [ ] `/changelog/` ve `/tr/changelog/` en üstte 0.6.0 bölümünü gösterir.
- [ ] **[karar]** Pages, Tanıtım Planı D6'ya göre hâlâ kapalı (404); yukarıdaki
      hiçbir adrese ulaşmak için depo ayarı *Pages › Source: GitHub Actions*
      açık olmalı. `pages.yml` `--strict` derler; kırık bir belge bağlantısı
      dağıtımı düşürür: Actions koşusuna bak.

### 9. README'de demo GIF

- [ ] `README.md` 42. satır `docs/media/en/demo.gif`'i göreli yolla gömer:
      dosya (254 KB) commit'li ve sürüm commit'inde, yani
      `github.com/cnkndmr/Deskmap`'te görünür. Türkçe kılavuz
      `docs/media/tr/demo.gif`'i gömer. Push'tan sonra iki sayfayı GitHub'da aç,
      GIF'in bir tur dönmesini izle.
- [ ] GIF çizildikten sonra arayüz değiştiyse: `make demo-media` (ffmpeg
      gerekir; `--shots --scenario demo`, yalnız demo verisi) ve `docs/media/`
      altındaki dört dosyayı commit'le.
- [ ] Release metni ve paylaşımlar GIF'e ham GitHub URL'siyle bağlanır
      (`https://raw.githubusercontent.com/cnkndmr/Deskmap/main/docs/media/en/demo.gif`);
      depo public olunca çalışır (Tanıtım Planı D1).

### 10. Gatekeeper ilk açılışı, yazılı hâli

- [ ] README *Install*, indirme sayfası (EN + TR) ve GitHub release metni
      gönderilen derlemeyle aynı ilk açılışı anlatır: ad-hoc → *bir kez aç, Yine
      de Aç, Erişim Ver, izin her güncellemede yeniden sorulur*; notarize →
      *sürükle, aç, Erişilebilirlik'i bir kez ver*.
- [ ] Release metninde özel API'ye ve bir macOS güncellemesinin masaüstü
      taşımayı bozabileceğine dair tek cümle, tanıtım metinlerindeki gibi.

### 11. Sonrasında

- [ ] Yayımlanan derlemeyi Can'ın kendi Mac'ine `make install` ile
      (`SIGN_IDENTITY` zorunlu; eski kopya `~/Documents/Deskmap/installed-copies/`'e
      konur) ya da zip'ten kur; günlük kopya gönderilenle aynı olsun.
- [ ] `docs/distribution.md`: sonundaki kısa listeyi buraya yönlendir.
- [ ] İki changelog'da yeni `[Unreleased]` bölümü açık (1. adım açtı).
- [ ] İlk issue'ları izle; Tanıtım Planı'nın 0. hafta notu geçerli: bu bir
      "açtım" duyurusu, tanıtım dalgası değil.
