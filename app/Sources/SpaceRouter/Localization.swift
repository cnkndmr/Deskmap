import Foundation

/// Kullanıcıya görünen metinler için tek giriş noktası.
///
/// Anahtar, İngilizce metnin kendisidir (İngilizce varsayılan dil). Paketteki
/// `tr.lproj/Localizable.strings` kullanıcının dil tercihine göre seçilir
/// (`build-app.sh`, `app/Resources/*.lproj` klasörlerini `.app`'e kopyalar).
/// Çeviri yoksa ya da paket dışında çalışılıyorsa (`swift test`, `swift run`)
/// anahtar, yani İngilizce metin döner.
///
/// Kurallar (`LocalizationTests` denetler):
/// - Anahtar tek parça bir dize sabitidir: birleştirme (`+`) ya da `\(...)` yok.
/// - Değişken kısımlar biçim belirteçleriyle verilir (`%@`, `%ld`); Türkçe
///   değer aynı belirteçleri taşır (sıra değişecekse `%1$@`, `%2$ld`).
/// - Tamsayılar `%ld` ile (Swift `Int`); `CGWindowID` önce `Int`'e çevrilir.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}

/// Biçimli metin; anahtar `String(format:)` kalıbıdır.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
