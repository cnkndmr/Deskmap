# Space Router — sık kullanılan komutlar.

PROJECT := SpaceRouter

.PHONY: help app run check test dist clean

help:
	@echo "make app        Menü çubuğu uygulamasını derle (build/SpaceRouter.app)"
	@echo "make run        Derleyip çalıştır"
	@echo "make check      Debug derlemesi"
	@echo "make test       Birim testleri (swift test)"
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

dist:
	@./scripts/make-dist.sh

clean:
	@rm -rf build app/.build
	@echo "Temizlendi."
