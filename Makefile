# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help install uninstall app run clean check test

help:
	@echo "make install    Hammerspoon motorunu kur ve rules.json oluştur"
	@echo "make app        SwiftUI menü çubuğu uygulamasını derle"
	@echo "make run        Uygulamayı derleyip çalıştır"
	@echo "make test       Motor mantığı testleri (macOS gerekmez)"
	@echo "make check      Sözdizimi + testler + Swift derlemesi"
	@echo "make uninstall  Hammerspoon entegrasyonunu kaldır"
	@echo "make clean      Derleme çıktılarını sil"

install:
	@./scripts/install.sh

uninstall:
	@./scripts/uninstall.sh

app:
	@./scripts/build-app.sh release

run: app
	@open build/$(PROJECT).app

test:
	@lua engine/tests/spec.lua

check:
	@./scripts/check.sh

clean:
	@rm -rf build app/.build
	@echo "Temizlendi."
