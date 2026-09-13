# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help app run check test concurrency-check dist clean

help:
	@echo "make app        Build the menu bar app (build/SpaceRouter.app)"
	@echo "make run        Build and open it"
	@echo "make check      Debug build"
	@echo "make test       Unit tests (swift test)"
	@echo "make concurrency-check"
	@echo "                Strict concurrency warnings (-strict-concurrency=complete; report only)"
	@echo "make dist       Distributable package: universal build + signing + zip (build/dist)"
	@echo "                FORMAT=dmg|both  VERSION=x.y.z  SIGN_IDENTITY=...  NOTARY_PROFILE=..."
	@echo "make clean      Delete build output"

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
	    || echo "No strict concurrency warnings."
	@echo "Warning count: $$(grep -E ': warning: ' app/.build/strict.log | sort -u | wc -l | tr -d ' ')"

dist:
	@./scripts/make-dist.sh

clean:
	@rm -rf build app/.build
	@echo "Cleaned."
