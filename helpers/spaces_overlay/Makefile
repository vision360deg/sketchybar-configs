SERVICE := com.vision3.sketchybar.spaces
BINARY := bin/spaces_overlay
BUILD_DIR := build
PLIST_TEMPLATE := $(SERVICE).plist.in
PLIST := $(HOME)/Library/LaunchAgents/$(SERVICE).plist
LOG_DIR := $(HOME)/Library/Logs/SketchyBar
MODULE_CACHE := /tmp/sketchybar-spaces-module-cache
SOURCES := OverlayState.swift SpacesView.swift OverlayWindowPolicy.swift OverlayPanel.swift main.swift

.PHONY: all clean test install-service uninstall-service render-service

all: $(BINARY)

$(BUILD_DIR)/bridge.o: bridge.c bridge.h | $(BUILD_DIR)
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) clang -std=c99 -O2 -Wall -Wextra -Werror -c bridge.c -o $@

$(BINARY): $(SOURCES) $(BUILD_DIR)/bridge.o bridge.h | bin
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc -O \
		-import-objc-header bridge.h \
		-framework AppKit -framework CoreGraphics \
		$(SOURCES) $(BUILD_DIR)/bridge.o -o $@

$(BUILD_DIR) bin:
	mkdir -p $@

test:
	CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE) SWIFT_MODULECACHE_PATH=$(MODULE_CACHE) xcrun swiftc \
		-framework AppKit \
		OverlayState.swift OverlayWindowPolicy.swift test/SpacesOverlayTests.swift -o /tmp/spaces-overlay-tests
	/tmp/spaces-overlay-tests

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
