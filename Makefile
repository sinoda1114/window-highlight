.PHONY: icon build test app verify install launch settings run e2e chrome-e2e open-privacy reset-accessibility reset-preferences high-visibility clean

APP_NAME := WindowHighlight
APP_BUNDLE_ID := local.sinoda.window-highlight
CONFIGURATION := release
APP_DIR := dist/$(APP_NAME).app
INSTALL_DIR := /Applications/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
BINARY := dist/$(APP_NAME)
ICONSET := Resources/$(APP_NAME).iconset
ICON := Resources/$(APP_NAME).icns

icon:
	swift Scripts/generate_app_icon.swift
	iconutil -c icns "$(ICONSET)" -o "$(ICON)"

build:
	mkdir -p dist
	swiftc -O -parse-as-library -framework AppKit -framework ApplicationServices Sources/WindowHighlight/*.swift -o "$(BINARY)"

test:
	mkdir -p dist
	swiftc -parse-as-library Sources/WindowHighlight/CoordinateConverter.swift Tests/WindowHighlightTests/CoordinateConverterTestRunner.swift -o dist/CoordinateConverterTests
	dist/CoordinateConverterTests

app: build icon
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BINARY)" "$(MACOS_DIR)/$(APP_NAME)"
	cp Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp "$(ICON)" "$(RESOURCES_DIR)/$(APP_NAME).icns"
	codesign --force --deep --sign - "$(APP_DIR)"

verify: app
	codesign --verify --deep --strict --verbose=2 "$(APP_DIR)"
	codesign -dv --verbose=4 "$(APP_DIR)"
	spctl --assess --type execute --verbose=4 "$(APP_DIR)" || true

install: app
	pkill -x "$(APP_NAME)" || true
	rm -rf "$(INSTALL_DIR)"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)"
	codesign --force --deep --sign - "$(INSTALL_DIR)"
	codesign --verify --deep --strict --verbose=2 "$(INSTALL_DIR)"

launch:
	open "$(INSTALL_DIR)"

settings:
	pkill -x "$(APP_NAME)" || true
	open "$(INSTALL_DIR)" --args --settings

run: install launch

e2e: test verify install launch
	sleep 2
	pgrep -fl "$(INSTALL_DIR)/Contents/MacOS/$(APP_NAME)"

chrome-e2e: e2e
	defaults write "$(APP_BUNDLE_ID)" enabled -bool true
	defaults write "$(APP_BUNDLE_ID)" borderEnabled -bool true
	defaults write "$(APP_BUNDLE_ID)" applyToAllDisplays -bool true
	defaults write "$(APP_BUNDLE_ID)" borderWidth -float 4
	defaults write "$(APP_BUNDLE_ID)" colorRed -float 0.01680417731
	defaults write "$(APP_BUNDLE_ID)" colorGreen -float 0.1983509958
	defaults write "$(APP_BUNDLE_ID)" colorBlue -float 1
	defaults write "$(APP_BUNDLE_ID)" colorAlpha -float 1
	pkill -x "$(APP_NAME)" || true
	open "$(INSTALL_DIR)"
	sleep 1
	swift Scripts/verify_chrome_highlight.swift

open-privacy:
	open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

reset-accessibility:
	tccutil reset Accessibility "$(APP_BUNDLE_ID)"

reset-preferences:
	defaults delete "$(APP_BUNDLE_ID)" || true

high-visibility:
	defaults write "$(APP_BUNDLE_ID)" enabled -bool true
	defaults write "$(APP_BUNDLE_ID)" borderEnabled -bool true
	defaults write "$(APP_BUNDLE_ID)" borderWidth -float 18
	defaults write "$(APP_BUNDLE_ID)" colorRed -float 1
	defaults write "$(APP_BUNDLE_ID)" colorGreen -float 0
	defaults write "$(APP_BUNDLE_ID)" colorBlue -float 0.85
	defaults write "$(APP_BUNDLE_ID)" colorAlpha -float 1
	pkill -x "$(APP_NAME)" || true
	open "$(INSTALL_DIR)"

clean:
	rm -rf .build dist
