APP      = MacBlinker
SRC_DIR  = Sources/MacBlinker
SOURCES  = $(SRC_DIR)/main.swift \
           $(SRC_DIR)/AppDelegate.swift \
           $(SRC_DIR)/BlinkerSettings.swift \
           $(SRC_DIR)/BlinkerRenderer.swift \
           $(SRC_DIR)/StatusBarController.swift \
           $(SRC_DIR)/FloatingOverlayController.swift \
           $(SRC_DIR)/CoachingHUDController.swift \
           $(SRC_DIR)/SpeechRateMonitor.swift \
           $(SRC_DIR)/PreferencesWindowController.swift

ARCH     = $(shell uname -m)
TARGET   = $(ARCH)-apple-macos12.0
SDK      = $(shell xcrun --show-sdk-path --sdk macosx)

APP_BUNDLE    = $(APP).app
CONTENTS      = $(APP_BUNDLE)/Contents
MACOS_DIR     = $(CONTENTS)/MacOS
RESOURCES_DIR = $(CONTENTS)/Resources
INSTALL_DIR   = $(HOME)/Applications

.PHONY: build run install uninstall clean

build:
	mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	swiftc $(SOURCES) \
		-sdk $(SDK) \
		-target $(TARGET) \
		-framework AVFoundation \
		-framework Speech \
		-o $(MACOS_DIR)/$(APP)
	cp Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	# Strip Finder metadata (.DS_Store/xattrs) that trips up codesign
	xattr -crs $(APP_BUNDLE)
	# Ad-hoc code sign so Gatekeeper accepts the app
	codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	open $(APP_BUNDLE)

install: build
	@echo "Installing to $(INSTALL_DIR)..."
	mkdir -p $(INSTALL_DIR)
	# Kill any running instance first
	-pkill $(APP) 2>/dev/null; sleep 0.5
	# Remove any existing bundle first — cp -r into an existing dir nests
	# the new bundle inside the old one instead of replacing it.
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	cp -r $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Done — MacBlinker is now in ~/Applications."
	@echo "To launch at login: System Settings → General → Login Items → add MacBlinker."
	open $(INSTALL_DIR)/$(APP_BUNDLE)

uninstall:
	-pkill $(APP) 2>/dev/null
	rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Uninstalled $(APP)."

clean:
	rm -rf $(APP_BUNDLE)
