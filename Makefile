.PHONY: gen build test archive install dmg clean lint

XCODE_PROJECT := Dyktando.xcodeproj
SCHEME := Dyktando
BUILD_DIR := build
ARCHIVE := $(BUILD_DIR)/Dyktando.xcarchive
EXPORT_DIR := $(BUILD_DIR)/Export
APP := $(ARCHIVE)/Products/Applications/Dyktando.app
# Stały podpis (Developer ID) = uprawnienia macOS (mikrofon, Dostępność) przeżywają aktualizacje.
# Podpis ad-hoc zmienia się z każdym buildem i macOS traktuje każdą wersję jak nową aplikację.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $$2; exit}')

gen:
	xcodegen generate

build: gen
	xcodebuild \
	  -project $(XCODE_PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Debug \
	  -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR) \
	  build

test: gen
	xcodebuild test \
	  -project $(XCODE_PROJECT) \
	  -scheme $(SCHEME) \
	  -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR)

archive: gen
	xcodebuild archive \
	  -project $(XCODE_PROJECT) \
	  -scheme $(SCHEME) \
	  -configuration Release \
	  -archivePath $(ARCHIVE) \
	  -destination 'platform=macOS' \
	  CODE_SIGN_IDENTITY=-

install: archive
	@test -n "$(SIGN_ID)" || (echo "Brak certyfikatu Developer ID — podaj SIGN_ID=<hash> albo SIGN_ID=- (ad-hoc)"; exit 1)
	codesign --force --options runtime --entitlements Dyktando/Dyktando.entitlements --sign "$(SIGN_ID)" "$(APP)"
	codesign -d --entitlements - "$(APP)" | grep -q audio-input
	-pkill -x Dyktando
	rm -rf /Applications/Dyktando.app
	ditto "$(APP)" /Applications/Dyktando.app
	open /Applications/Dyktando.app

dmg: archive
	SIGN_ID="$(SIGN_ID)" ./scripts/make-dmg.sh $(ARCHIVE) $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) Dyktando.xcodeproj *.dmg
