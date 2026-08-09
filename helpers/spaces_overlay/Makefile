SERVICE := com.vision3.sketchybar.spaces
APP_DIR := bin/spaces_overlay.app
BINARY := $(APP_DIR)/Contents/MacOS/spaces_overlay
INFO_PLIST := $(APP_DIR)/Contents/Info.plist
BUILD_DIR := build
PLIST_TEMPLATE := $(SERVICE).plist.in
PLIST := $(HOME)/Library/LaunchAgents/$(SERVICE).plist
LOG_DIR := $(HOME)/Library/Logs/SketchyBar
MODULE_CACHE := /tmp/sketchybar-spaces-module-cache
SOURCES := OverlayState.swift WindowCarouselModel.swift WindowCapture.swift WindowCarouselView.swift SpacesView.swift OverlayWindowPolicy.swift OverlayPanel.swift main.swift

.PHONY: all clean test test-window-capture test-reorder install-service uninstall-service render-service

all: $(BINARY)

$(BUILD_DIR)/bridge.o: bridge.c bridge.h | $(BUILD_DIR)
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) clang -std=c99 -O2 -Wall -Wextra -Werror -c bridge.c -o $@

$(BINARY): $(SOURCES) $(BUILD_DIR)/bridge.o bridge.h $(INFO_PLIST) | $(APP_DIR)/Contents/MacOS
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc -O \
		-import-objc-header bridge.h \
		-framework AppKit -framework CoreGraphics -framework ScreenCaptureKit \
		$(SOURCES) $(BUILD_DIR)/bridge.o -o $@
	printf '%s\n' 'designated => identifier "$(SERVICE)"' | \
		/usr/bin/codesign --force --deep --sign - --identifier $(SERVICE) -r - "$(APP_DIR)"


$(INFO_PLIST): Info.plist | $(APP_DIR)/Contents
	cp Info.plist "$@"

$(BUILD_DIR) $(APP_DIR)/Contents $(APP_DIR)/Contents/MacOS:
	mkdir -p $@

test: test-window-capture
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc \
		-framework AppKit -framework ScreenCaptureKit \
		OverlayState.swift WindowCarouselModel.swift WindowCapture.swift WindowCarouselView.swift OverlayWindowPolicy.swift test/SpacesOverlayTests.swift test/WindowCarouselTests.swift -o /tmp/spaces-overlay-tests
	/tmp/spaces-overlay-tests

test-window-capture:
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc \
		-framework AppKit -framework CoreGraphics -framework ScreenCaptureKit WindowCapture.swift test/WindowCaptureTests.swift -o /tmp/window-capture-tests
	/tmp/window-capture-tests

test-reorder:
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc \
		-framework CoreGraphics OverlayState.swift ../../tests/spaces_overlay_reorder_test.swift -o /tmp/spaces-overlay-reorder-tests
	/tmp/spaces-overlay-reorder-tests

render-service: $(BINARY)
	mkdir -p "$(dir $(PLIST))" "$(LOG_DIR)"
	sed \
		-e 's|@EXECUTABLE@|$(abspath $(BINARY))|g' \
		-e 's|@STDOUT@|$(LOG_DIR)/spaces-overlay.out.log|g' \
		-e 's|@STDERR@|$(LOG_DIR)/spaces-overlay.err.log|g' \
		$(PLIST_TEMPLATE) > "$(PLIST)"
	plutil -lint "$(PLIST)"

install-service: render-service
	-launchctl bootout gui/$(shell id -u)/$(SERVICE) 2>/dev/null
	launchctl bootstrap gui/$(shell id -u) "$(PLIST)"

uninstall-service:
	-launchctl bootout gui/$(shell id -u)/$(SERVICE) 2>/dev/null
	rm -f "$(PLIST)"

clean:
	rm -rf $(BUILD_DIR) bin
