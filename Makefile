# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help install uninstall app run clean check

help:
	@echo "make install    Hammerspoon motorunu kur ve rules.json oluştur"
	@echo "make app        SwiftUI menü çubuğu uygulamasını derle"
	@echo "make run        Uygulamayı derleyip çalıştır"
	@echo "make check      Lua sözdizimi + JSON doğrulaması"
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

check:
	@./scripts/check.sh

clean:
	@rm -rf build app/.build
	@echo "Temizlendi."
