.PHONY: build test app run dmg

build:
	swift build

test:
	swift test

app:
	bash scripts/bundle.sh release

run: app
	open dist/ClueLiz.app

dmg: app
	bash scripts/make-dmg.sh
