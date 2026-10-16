# Deskmap — sık kullanılan komutlar.

PROJECT := Deskmap

.PHONY: help app run install logs measure-idle sample url check test concurrency-check dist site site-serve site-shots clean

help:
	@echo "make app        Build the menu bar app (build/$(PROJECT).app)"
	@echo "make run        Build and open it"
	@echo "make install    Build, set the old /Applications copy aside, install and open"
	@echo "                SIGN_IDENTITY=... required (ad-hoc drops Accessibility permission)"
	@echo "make logs       Last LOG_WINDOW (default 10m) of the app's unified log"
	@echo "make measure-idle"
	@echo "                Idle CPU of the running app over IDLE_SECONDS (default 600) via ps"
	@echo "make url URL=deskmap://reapply"
	@echo "                Send an automation URL to the running app"
	@echo "make check      Debug build"
	@echo "make test       Unit tests (swift test)"
	@echo "make concurrency-check"
	@echo "                Strict concurrency warnings (-strict-concurrency=complete; report only)"
	@echo "make dist       Distributable package: universal build + signing + zip (build/dist)"
	@echo "                FORMAT=dmg|both  VERSION=x.y.z  SIGN_IDENTITY=...  NOTARY_PROFILE=..."
	@echo "make site       Build the website into website/_site (Node + pandoc)"
	@echo "make site-serve Build it and serve it on http://localhost:$(SITE_PORT)"
	@echo "make site-shots Website screenshots, dark and light (website/shots)"
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
	@for pid in $$(pgrep -x $(PROJECT)); do kill $$pid; done; true
	@if [ -d "$(INSTALL_DIR)/$(PROJECT).app" ]; then \
	    mkdir -p "$(ARCHIVE_DIR)"; \
	    dest="$(ARCHIVE_DIR)/$(PROJECT)-$$(date +%Y%m%d-%H%M%S).app"; \
	    mv "$(INSTALL_DIR)/$(PROJECT).app" "$$dest" && echo "Old copy set aside: $$dest"; \
	fi
	@ditto build/$(PROJECT).app "$(INSTALL_DIR)/$(PROJECT).app"
	@echo "Installed: $(INSTALL_DIR)/$(PROJECT).app"
	@open "$(INSTALL_DIR)/$(PROJECT).app"

LOG_WINDOW ?= 10m
logs:
	@/usr/bin/log show --predicate 'subsystem == "com.deskmap.app"' --last $(LOG_WINDOW) --info --style compact

# Boşta CPU: `ps -o time=` farkı / geçen süre (tek çekirdeğin yüzdesi) ve RSS.
# Ölçüm sırasında bilgisayara dokunulmamalı.
IDLE_SECONDS ?= 600
measure-idle:
	@pid=$$(pgrep -x $(PROJECT)) || { echo "$(PROJECT) is not running"; exit 1; }; \
	secs() { ps -o time= -p $$pid | awk -F'[:.]' '{ if (NF==4) print $$1*3600+$$2*60+$$3+$$4/100; else print $$1*60+$$2+$$3/100 }'; }; \
	t0=$$(secs); echo "pid $$pid, cpu time $$t0 s, waiting $(IDLE_SECONDS) s"; \
	sleep $(IDLE_SECONDS); t1=$$(secs); rss=$$(ps -o rss= -p $$pid | tr -d ' '); \
	echo "cpu time $$t1 s"; \
	awk -v a=$$t0 -v b=$$t1 -v s=$(IDLE_SECONDS) -v r=$$rss 'BEGIN { printf "idle CPU: %.3f%% of one core over %d s, RSS %.1f MB\n", (b-a)*100/s, s, r/1024 }'

# Çağrı ağacı örneği (SAMPLE_SECONDS, varsayılan 10); build/sample.txt'e yazar.
SAMPLE_SECONDS ?= 10
sample:
	@pid=$$(pgrep -x $(PROJECT)) || { echo "$(PROJECT) is not running"; exit 1; }; \
	/usr/bin/sample $$pid $(SAMPLE_SECONDS) -file $(CURDIR)/build/sample.txt >/dev/null 2>&1; \
	echo "written: build/sample.txt"

url:
	@test -n "$(URL)" || { echo "URL=deskmap://... is required"; exit 1; }
	@open "$(URL)"

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

# Web sitesi: website/ kaynağından website/_site'a (gitignore'da). Bağlantılar
# göreli olduğundan alt yolda (GitHub Pages /Deskmap/) da çalışır.
SITE_PORT ?= 8766
site:
	@node scripts/build-site.mjs

# SITE_URL bu sunucuya göre verilir; yoksa 404.html'nin /Deskmap/... mutlak
# bağlantıları yerelde kırılır.
site-serve:
	@SITE_URL=http://localhost:$(SITE_PORT)/ node scripts/build-site.mjs
	@echo "Serving http://localhost:$(SITE_PORT)/ (Ctrl-C to stop)"
	@python3 -m http.server $(SITE_PORT) --directory website/_site

# Sitenin ekran görüntüleri, koyu ve açık görünümde (website/shots/<dil>/ ve
# .../light/), uygulamanın --shots kipiyle çizilir, en çok 1600 px. Arayüz
# değişince çalıştır ve website/shots'u commit'le.
site-shots: app
	@./scripts/site-shots.sh

clean:
	@rm -rf build app/.build website/_site
	@echo "Cleaned."
