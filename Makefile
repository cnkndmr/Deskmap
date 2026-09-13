# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help app run check test concurrency-check dist clean

help:
	@echo "make app        Menü çubuğu uygulamasını derle (build/SpaceRouter.app)"
	@echo "make run        Derleyip çalıştır"
	@echo "make check      Debug derlemesi"
	@echo "make test       Birim testleri (swift test)"
	@echo "make concurrency-check"
	@echo "                Sıkı eşzamanlılık uyarıları (-strict-concurrency=complete; yalnızca rapor)"
	@echo "make dist       Gönderilebilir paket: evrensel derleme + imza + zip (build/dist)"
	@echo "                FORMAT=dmg|both  VERSION=x.y.z  SIGN_IDENTITY=...  NOTARY_PROFILE=..."
	@echo "make clean      Derleme çıktılarını sil"

app:
	@./scripts/build-app.sh release

run: app
	@open build/$(PROJECT).app

check:
	@swift build --package-path app -c debug

test:
	@swift test --package-path app

# Swift 6 hazırlığı: sıkı eşzamanlılık uyarılarını listeler, derleme ayarını
# değiştirmez. Ayrı ve her seferinde temiz bir derleme dizini kullanır; yoksa
# artımlı derleme değişmeyen dosyaların uyarılarını yeniden basmaz.
concurrency-check:
	@mkdir -p app/.build && rm -rf app/.build/strict
	@swift build --package-path app -c debug --scratch-path app/.build/strict \
	    -Xswiftc -strict-concurrency=complete > app/.build/strict.log 2>&1 \
	    || { cat app/.build/strict.log; exit 1; }
	@grep -E ': warning: ' app/.build/strict.log | sort -u \
	    || echo "Sıkı eşzamanlılık uyarısı yok."
	@echo "Uyarı sayısı: $$(grep -E ': warning: ' app/.build/strict.log | sort -u | wc -l | tr -d ' ')"

dist:
	@./scripts/make-dist.sh

clean:
	@rm -rf build app/.build
	@echo "Temizlendi."
