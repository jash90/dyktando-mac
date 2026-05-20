.PHONY: gen build test archive dmg clean lint

XCODE_PROJECT := Dyktando.xcodeproj
SCHEME := Dyktando
BUILD_DIR := build
ARCHIVE := $(BUILD_DIR)/Dyktando.xcarchive
EXPORT_DIR := $(BUILD_DIR)/Export

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

dmg: archive
	./scripts/make-dmg.sh $(ARCHIVE) $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) Dyktando.xcodeproj *.dmg
