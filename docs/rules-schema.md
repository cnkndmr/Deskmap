# rules.json şeması

Tek kaynak dosya. SwiftUI uygulaması yazar, Hammerspoon motoru okur ve
dosya değiştiğinde otomatik yeniden yükler.

Konum: `~/Library/Application Support/SpaceRouter/rules.json`

## Üst seviye

| Alan | Tip | Açıklama |
|---|---|---|
| `version` | int | Şema sürümü. Şu an `1`. |
| `settings` | object | Genel davranış ayarları. |
| `screens` | array | Bilinen ekranların UUID kaydı. |
| `rules` | array | Workspace → hedef eşlemeleri. |

## settings

| Alan | Tip | Varsayılan | Açıklama |
|---|---|---|---|
| `enabled` | bool | `true` | Motoru tamamen açar/kapatır. |
| `debounceSeconds` | number | `0.4` | Art arda gelen başlık olaylarını tek işleme indirger. |
| `screenSettleSeconds` | number | `2.5` | Monitör takma/çıkarma sonrası bekleme. |
| `moveSettleSeconds` | number | `0.25` | Ekran değişimi ile Space taşıma arası bekleme. |
| `notifications` | bool | `true` | Taşıma sonrası bildirim gösterir. |
| `logLevel` | string | `"info"` | `debug` / `info` / `warning` / `error`. |
| `followWindowAfterMove` | bool | `false` | `true` ise taşımadan sonra hedef Space'e geçilir. |

## screens[]

| Alan | Tip | Açıklama |
|---|---|---|
| `id` | string | Kurallarda referans verilen kimlik. |
| `role` | string | `builtin` veya `external`. Dock tespiti bu alana bakar. |
| `name` | string | Sadece görüntüleme amaçlı. |
| `uuid` | string | `hs.screen:getUUID()` değeri. Eşleşme bunun üzerinden yapılır. |

`role: "external"` olan ekranlardan **en az biri** bağlıysa sistem *docked*
kabul edilir; hiçbiri bağlı değilse *undocked*.

## rules[]

| Alan | Tip | Açıklama |
|---|---|---|
| `id` | string | Benzersiz kimlik. |
| `name` | string | Görünen ad. |
| `enabled` | bool | Kural aktif mi. |
| `app` | object/string | Hangi uygulamanın pencereleri. |
| `match` | object | Pencere başlığı eşleştirme kuralı. |
| `docked` | object/null | Harici monitör bağlıyken hedef. |
| `undocked` | object/null | Harici monitör yokken hedef. |

`docked` veya `undocked` `null` bırakılırsa o durumda kural uygulanmaz.
Kurallar dizideki sırayla denenir; **ilk eşleşen kazanır**.

### app

```json
"app": { "name": "Code", "bundleID": "com.microsoft.VSCode" }
```

veya kısa biçim:

```json
"app": "Safari"
```

| Alan | Zorunlu | Açıklama |
|---|---|---|
| `name` | evet | macOS uygulama adı. Pencere izleyicisi bununla çalışır. |
| `bundleID` | hayır | Verilirse eşleşme bunun üzerinden **kesin** yapılır. |

`name` ile uygulamanın Finder'daki dosya adı aynı olmayabilir. Örneğin
Visual Studio Code'un uygulama adı `Code`'dur. Doğru değeri menü
çubuğundaki **"TÜM pencereleri konsola yaz"** komutu gösterir.

### match

| `type` | Davranış |
|---|---|
| `contains` | Başlık `value` metnini içeriyorsa (düz metin, harf duyarlı). |
| `prefix` | Başlık `value` ile başlıyorsa. |
| `suffix` | Başlık `value` ile bitiyorsa. |
| `exact` | Başlık tam olarak `value` ise. |
| `pattern` | `value` bir **Lua deseni** olarak uygulanır. |

Lua desenlerinde `( ) . % + - * ? [ ] ^ $` karakterleri özeldir ve
`%` ile kaçırılır. Örnek: `"%[Workspace%] scratch"`.

### docked / undocked

| Alan | Tip | Açıklama |
|---|---|---|
| `screen` | string | `screens[].id` referansı. Bulunamazsa ana ekran kullanılır. |
| `desktop` | int | O ekrandaki **normal** Desktop sırası (1 tabanlı). Tam ekran Space'ler sayılmaz. |
| `layout` | object | `x`, `y`, `w`, `h` — ekranın kullanılabilir alanına göre 0..1 oranları. |

### Hazır layout oranları

```
Tam           { "x": 0,   "y": 0,   "w": 1,    "h": 1    }
Sol yarı      { "x": 0,   "y": 0,   "w": 0.5,  "h": 1    }
Sağ yarı      { "x": 0.5, "y": 0,   "w": 0.5,  "h": 1    }
Sol %70       { "x": 0,   "y": 0,   "w": 0.7,  "h": 1    }
Sağ %30       { "x": 0.7, "y": 0,   "w": 0.3,  "h": 1    }
Orta %80      { "x": 0.1, "y": 0.1, "w": 0.8,  "h": 0.8  }
Üst yarı      { "x": 0,   "y": 0,   "w": 1,    "h": 0.5  }
Alt yarı      { "x": 0,   "y": 0.5, "w": 1,    "h": 0.5  }
```
