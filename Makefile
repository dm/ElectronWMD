GREEN  := \033[32m
YELLOW := \033[33m
RED    := \033[31m
CYAN   := \033[36m
NC     := \033[0m

UNAME        := $(shell uname)
VERSION      := $(shell node -p "require('./package.json').version" 2>/dev/null)
# npm writes node_modules/.package-lock.json after every successful install.
# Make re-runs the install when package.json or package-lock.json is newer than it.
NODE_MODULES := node_modules/.package-lock.json
SUBMODULE    := webminidisc/package.json

.DEFAULT_GOAL := help

.PHONY: help install submodules doctor \
        dev build renderer typecheck fmt fmt-check \
        test itest audit ci \
        pack dist dist-mac release \
        clean clean-renderer clean-all

help: ## Display this help screen
	@printf '$(CYAN)ElectronWMD $(VERSION)$(NC)\n\n'
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make $(GREEN)<target>$(NC)\n"} \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } \
		/^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-16s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\n$(YELLOW)Order$(NC)\n'
	@printf '  new machine     $(GREEN)doctor$(NC) -> $(GREEN)install$(NC)\n'
	@printf '  day to day      $(GREEN)dev$(NC) (builds renderer once, then tsc + electron)\n'
	@printf '  before pushing  $(GREEN)ci$(NC)\n'
	@printf '  release         $(GREEN)release$(NC) VERSION=x.y.z -> tag push -> GitHub Actions draft release\n'
	@printf '\n  $(GREEN)build$(NC)/$(GREEN)dev$(NC) run scripts/run-fixes.sh, which needs $(RED)gsed$(NC) on macOS (brew install gnu-sed).\n'

##@ Setup

$(SUBMODULE):
	git submodule update --init --recursive

$(NODE_MODULES): package.json package-lock.json
	npm install

submodules: $(SUBMODULE) ## Initialise the webminidisc renderer submodule

install: $(SUBMODULE) $(NODE_MODULES) ## Install dependencies (auto-triggered by the targets that need them)

doctor: ## Check the toolchain for this machine
	@printf 'node      '; node -v 2>/dev/null || printf '$(RED)missing$(NC)\n'
	@printf 'npm       '; npm -v 2>/dev/null || printf '$(RED)missing$(NC)\n'
	@if [ "$(UNAME)" = "Darwin" ]; then \
		printf 'gsed      '; command -v gsed >/dev/null && printf '$(GREEN)ok$(NC)\n' || printf '$(RED)missing$(NC) (brew install gnu-sed)\n'; \
		printf 'xcode cli '; xcode-select -p >/dev/null 2>&1 && printf '$(GREEN)ok$(NC)\n' || printf '$(RED)missing$(NC) (xcode-select --install)\n'; \
	fi
	@printf 'submodule '; [ -f $(SUBMODULE) ] && printf '$(GREEN)ok$(NC)\n' || printf '$(YELLOW)not initialised$(NC) (make submodules)\n'
	@printf 'renderer  '; [ -d renderer ] && printf '$(GREEN)built$(NC)\n' || printf '$(YELLOW)not built$(NC) (make renderer)\n'
	@printf 'usb       '; node -e "require('usb'); console.log('ok')" 2>/dev/null || printf '$(RED)fails to load$(NC) (npm install-scripts approve usb && npm rebuild usb)\n'

##@ Development

dev: install ## Build and run the app with NODE_ENV=development
	npm start

build: install ## Build renderer (if missing), apply fixes, compile TypeScript
	npm run build

renderer: install ## Force a rebuild of the webminidisc renderer
	rm -rf renderer
	./scripts/build-renderer.sh

typecheck: $(NODE_MODULES) ## Type-check without emitting
	npx tsc --noEmit -p .

fmt: $(NODE_MODULES) ## Format src/ with prettier
	npx prettier --write "src/**/*.ts"

fmt-check: $(NODE_MODULES) ## Check formatting (src/wmd/original/ is ignored: copied from webminidisc)
	npx prettier --check "src/**/*.ts"

##@ Test & CI

test: $(NODE_MODULES) ## Compile TypeScript, then run the unit tests
	npx tsc -p .
	node scripts/test-socket-path.js

itest: test ## macOS only: spawn the server, wait for its socket, connect
ifeq ($(UNAME),Darwin)
	node scripts/itest-server.js
else
	@printf '$(YELLOW)itest is macOS-only, skipping$(NC)\n'
endif

audit: $(NODE_MODULES) ## npm audit (fails on moderate or above)
	npm audit --audit-level=moderate

ci: ## Everything a push should pass: audit, formatting, typecheck, tests
	@printf '$(CYAN)Running CI checks...$(NC)\n'
	@$(MAKE) --no-print-directory audit fmt-check typecheck test
	@printf '$(GREEN)All CI checks passed.$(NC)\n'

##@ Package & Release

pack: install ## Unpacked build in build/ for a quick local smoke test
	npm run pack

dist: install ## Windows + Linux x64 packages (what CI runs on ubuntu)
	npm run dist

dist-mac: install ## macOS x64 + arm64 packages (what CI runs on macos)
	npm run dist-mac

release: ## Tag and push VERSION to trigger the GitHub release workflow: make release VERSION=x.y.z
	@[ -n "$(filter command line,$(origin VERSION))" ] || { printf '$(RED)usage: make release VERSION=x.y.z$(NC)\n'; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { printf '$(RED)working tree is dirty$(NC)\n'; exit 1; }
	git tag -a "$(VERSION)" -m "Version $(VERSION)"
	git push origin "$(VERSION)"
	@printf '$(GREEN)Pushed tag $(VERSION).$(NC) The workflow creates a draft release.\n'

##@ Cleanup

clean: ## Remove dist/ and build/
	rm -rf dist build

clean-renderer: ## Remove the built renderer (next build rebuilds it)
	rm -rf renderer

clean-all: clean clean-renderer ## Also remove node_modules
	rm -rf node_modules
