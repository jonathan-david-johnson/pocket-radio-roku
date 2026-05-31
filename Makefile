# PocketStreams for Roku — dev Makefile
#
# Device creds via env (never committed):
#   export ROKU_HOST=10.99.99.50
#   export ROKU_PASS=your-dev-mode-password

ROKU_HOST ?= 10.99.99.50
ROKU_USER ?= rokudev
ZIP        = channel.zip
# Channel sources zipped at the root (no wrapping folder), if present.
SRC        = manifest source components images

.PHONY: help build zip install sideload deploy telnet debug screenshot clean
.DEFAULT_GOAL := help

help:
	@echo "PocketStreams (Roku) — make targets"
	@echo ""
	@echo "  build / zip    Package present channel sources into $(ZIP)"
	@echo "  install        Sideload $(ZIP) to the device (needs ROKU_PASS)"
	@echo "  deploy         build + install"
	@echo "  telnet/debug   Open BrightScript debug console (port 8085)"
	@echo "  screenshot     Pull a device screenshot to screenshot.jpg"
	@echo "  clean          Remove $(ZIP)"
	@echo ""
	@echo "  Env: ROKU_HOST=$(ROKU_HOST)  ROKU_USER=$(ROKU_USER)  ROKU_PASS=<unset?>"

build: zip
zip:
	@present=""; for p in $(SRC); do [ -e "$$p" ] && present="$$present $$p"; done; \
	if [ -z "$$present" ]; then \
		echo "No channel sources yet (expected: $(SRC)). Scaffold M1 first."; exit 1; \
	fi; \
	rm -f $(ZIP); \
	echo "Zipping:$$present"; \
	zip -r $(ZIP) $$present >/dev/null && echo "Wrote $(ZIP)"

# Sideload via the Development Application Installer (digest auth).
install:
	@if [ -z "$(ROKU_PASS)" ]; then echo "ROKU_PASS unset. export ROKU_PASS=<dev-mode password>"; exit 1; fi
	@if [ ! -f "$(ZIP)" ]; then echo "$(ZIP) missing — run 'make build' first"; exit 1; fi
	@echo "Installing $(ZIP) -> http://$(ROKU_HOST) ..."
	@curl -s --user "$(ROKU_USER):$(ROKU_PASS)" --digest \
		-F "mysubmit=Install" -F "archive=@$(ZIP)" \
		http://$(ROKU_HOST)/plugin_install \
		| grep -o 'Install Success\|Identical\|Failed' || echo "(no status — check device)"

sideload: install
deploy: build install

# BrightScript console: print output + crash backtraces.
telnet debug:
	@echo "Connecting to $(ROKU_HOST):8085 (Ctrl-] then 'quit' to exit)"
	@telnet $(ROKU_HOST) 8085

# Pull a screenshot from the dev device.
screenshot:
	@if [ -z "$(ROKU_PASS)" ]; then echo "ROKU_PASS unset"; exit 1; fi
	@curl -s --user "$(ROKU_USER):$(ROKU_PASS)" --digest \
		"http://$(ROKU_HOST)/pkgs/dev.jpg" -o screenshot.jpg \
		&& echo "Saved screenshot.jpg" || echo "Screenshot failed (channel must be sideloaded)"

clean:
	@rm -f $(ZIP) screenshot.jpg && echo "Cleaned"
