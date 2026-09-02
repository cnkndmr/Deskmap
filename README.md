# Space Router

Pencere başlığında görünen **workspace adına** göre pencereleri doğru
monitöre, doğru macOS Desktop'ına ve doğru düzene yerleştirir.

Uygulamadan bağımsızdır:

| Uygulama | Workspace kavramı |
|---|---|
| Safari | Tab Group |
| VS Code / Cursor | Workspace veya klasör |
| Obsidian | Vault |
| iTerm2 | Oturum profili |
| Slack, Notion, Figma | Workspace / dosya |

Kural şuna benzer:

```
Uygulama:  Code
Başlık:    "[WS] project-x" ile başlıyorsa

Harici monitör bağlıyken   -> External Monitor · Desktop 2 · tam alan
Harici monitör yokken      -> MacBook ekranı · Desktop 1 · ortada %90
```

Monitör takıldığında veya çıkarıldığında pencereler otomatik olarak
yeniden yerleştirilir.

## Proje yapısı

```
SpaceRouter/
├── engine/                  Hammerspoon motoru (Lua)
│   ├── spacerouter/         Modüller
│   └── hammerspoon-init-snippet.lua
├── app/                     SwiftUI menü çubuğu uygulaması
│   ├── Package.swift
│   └── Sources/SpaceRouter/
│       ├── Models/          rules.json veri modeli ve deposu
│       ├── Services/        Ekran, izin, pencere ve motor köprüsü
│       └── Views/           Kural editörü ve durum ekranları
├── config/rules.example.json
├── scripts/                 install / uninstall / build / check
└── docs/                    Kurulum, şema, şablonlar, sorun giderme
```

## İki katmanlı mimari

```
SwiftUI menü çubuğu uygulaması   (kuralları düzenler)
              │
              ▼
   ~/Library/Application Support/SpaceRouter/rules.json
              │
              ▼
Hammerspoon motoru               (pencereleri yerleştirir)
```

İki katman yalnızca bu JSON dosyası üzerinden konuşur. Uygulama dosyayı
yazar, motor değişikliği anında algılayıp kuralları yeniden yükler.

Bu ayrım bilinçlidir: bir pencereyi belirli bir macOS Space'e taşımanın
resmî public API'si yoktur. Space taşıma işi, bu işi zaten yapan
Hammerspoon'a bırakılmıştır. Ayrıntı: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Hızlı başlangıç

```bash
brew install --cask hammerspoon
make install        # motoru bağlar, rules.json oluşturur
make app            # menü çubuğu uygulamasını derler
open build/SpaceRouter.app
```

Ardım adım anlatım: [docs/SETUP.md](docs/SETUP.md)

## Belgeler

- [docs/SETUP.md](docs/SETUP.md) — kurulum ve ilk kural
- [docs/rules-schema.md](docs/rules-schema.md) — `rules.json` alanları
- [docs/app-presets.md](docs/app-presets.md) — uygulama başına başlık ipuçları
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — tasarım kararları ve sınırlar
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — sorun giderme

## Gereksinimler

- macOS 13 veya üzeri
- [Hammerspoon](https://www.hammerspoon.org)
- Xcode Command Line Tools (yalnızca uygulamayı derlemek için)
- Erişilebilirlik izni (Hammerspoon ve Space Router için)

## Lisans

MIT — bkz. [LICENSE](LICENSE)
