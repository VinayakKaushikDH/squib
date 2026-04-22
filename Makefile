APP_NAME  = Squib
DIST_DIR  = dist
APP_PATH  = $(DIST_DIR)/$(APP_NAME).app
CONTENTS  = $(APP_PATH)/Contents
ICON_SVG  = Sources/squib/Resources/AppIcon.svg
ICONSET   = $(DIST_DIR)/AppIcon.iconset

.PHONY: app install uninstall clean

app: ## Build a distributable .app bundle → dist/squib.app
	swift build -c release --product squib
	@rm -rf $(DIST_DIR)
	@mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	@cp .build/release/squib $(CONTENTS)/MacOS/squib
	@cp Sources/squib/Info.plist $(CONTENTS)/Info.plist
	@find .build/release -maxdepth 1 -name "*.bundle" -exec cp -r {} $(CONTENTS)/Resources/ \;
	@echo "Generating icon..."
	@swift Scripts/make-icon.swift $(ICON_SVG) $(ICONSET) $(CONTENTS)/Resources/AppIcon.icns
	@rm -rf $(ICONSET)
	@echo "Built: $(APP_PATH)"
	@echo "Run:   open $(APP_PATH)"
	@echo "Install: make install"

install: app ## Build and copy to ~/Applications/squib.app
	@rm -rf ~/Applications/$(APP_NAME).app
	@cp -r $(APP_PATH) ~/Applications/
	@echo "Installed: ~/Applications/$(APP_NAME).app"

uninstall: ## Remove ~/Applications/Squib.app
	@rm -rf ~/Applications/$(APP_NAME).app
	@echo "Removed: ~/Applications/$(APP_NAME).app"

clean: ## Remove dist/ and .build/
	rm -rf $(DIST_DIR) .build
