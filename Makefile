# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help app run check clean

help:
	@echo "make app        Menü çubuğu uygulamasını derle (build/SpaceRouter.app)"
	@echo "make run        Derleyip çalıştır"
	@echo "make check      Debug derlemesi"
	@echo "make clean      Derleme çıktılarını sil"

app:
	@./scripts/build-app.sh release

run: app
	@open build/$(PROJECT).app

check:
	@swift build --package-path app -c debug

clean:
	@rm -rf build app/.build
	@echo "Temizlendi."
