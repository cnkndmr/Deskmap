# Deskmap — sık kullanılan komutlar.

PROJECT := Deskmap

.PHONY: help app run install check test concurrency-check dist clean

help:
	@echo "make app        Build the menu bar app (build/$(PROJECT).app)"
	@echo "make run        Build and open it"
	@echo "make install    Build, set the old /Applications copy aside, install and open"
	@echo "                SIGN_IDENTITY=... required (ad-hoc drops Accessibility permission)"
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

# Kurulu kopya silinmez: kapatılır, tarih damgalı olarak ARCHIVE_DIR'e
# taşınır, yeni paket ditto ile kopyalanıp açılır. Ad-hoc imza Erişilebilirlik
# iznini düşürdüğü için kimlik zorunlu.
INSTALL_DIR ?= /Applications
ARCHIVE_DIR ?= $(HOME)/Documents/Archive/Deskmap/kurulu-kopyalar
export SIGN_IDENTITY

install:
	@test -n "$(SIGN_IDENTITY)" -a "$(SIGN_IDENTITY)" != "-" \
	    || { echo "SIGN_IDENTITY is required for install"; exit 1; }
	@./scripts/build-app.sh release
	@pkill -x $(PROJECT) || true
	@if [ -d "$(INSTALL_DIR)/$(PROJECT).app" ]; then \
	    mkdir -p "$(ARCHIVE_DIR)"; \
	    dest="$(ARCHIVE_DIR)/$(PROJECT)-$$(date +%Y%m%d-%H%M%S).app"; \
	    mv "$(INSTALL_DIR)/$(PROJECT).app" "$$dest" && echo "Old copy set aside: $$dest"; \
	fi
	@ditto build/$(PROJECT).app "$(INSTALL_DIR)/$(PROJECT).app"
	@echo "Installed: $(INSTALL_DIR)/$(PROJECT).app"
	@open "$(INSTALL_DIR)/$(PROJECT).app"

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
