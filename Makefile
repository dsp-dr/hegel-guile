# Makefile for hegel-guile
# Protocol: Hegel/0.7 | Version: 0.7.1

# Guile binary detection: guile3 (FreeBSD) then guile (macOS/Linux)
GUILE   ?= $(shell command -v guile3 2>/dev/null || command -v guile 2>/dev/null || echo guile)
GUILD   ?= $(shell command -v guild3 2>/dev/null || command -v guild 2>/dev/null || echo guild)
SRC_DIR := src
TEST_DIR:= tests
prefix  ?= /usr/local

# Detect Guile effective version (e.g. 3.0)
GUILE_EFFECTIVE_VERSION := $(shell $(GUILE) -c '(display (effective-version))' 2>/dev/null || echo 3.0)
sitedir  = $(prefix)/share/guile/site/$(GUILE_EFFECTIVE_VERSION)
ccachedir = $(prefix)/lib/guile/$(GUILE_EFFECTIVE_VERSION)/site-ccache

MODULES = hegel/crc32.scm hegel/cbor.scm hegel/packet.scm hegel/mux.scm \
          hegel/channel.scm hegel/protocol.scm hegel/generators.scm \
          hegel/server.scm hegel/test-case.scm hegel/test.scm
TOP_MODULE = hegel.scm

.PHONY: all compile test test-all check check-verbose repl clean tangle \
        install install-src uninstall lint lint-docs lint-contracts help

all: compile

compile:
	$(GUILD) compile -L $(SRC_DIR) $(addprefix $(SRC_DIR)/,$(MODULES) $(TOP_MODULE))

test: compile
	@for f in $(TEST_DIR)/test-*.scm; do \
		echo "=== Running $$f ==="; \
		$(GUILE) -L $(SRC_DIR) "$$f" || exit 1; \
	done

test-all: test

# guile-sage convention: `check` is the canonical test target
check: test

check-verbose: compile
	@for f in $(TEST_DIR)/test-*.scm; do \
		echo "=== Running $$f ==="; \
		$(GUILE) -L $(SRC_DIR) "$$f"; \
		echo "    exit: $$?"; \
	done

repl:
	$(GUILE) -L $(SRC_DIR)

# Lint targets
lint: lint-docs lint-contracts

lint-docs:
	@./scripts/doc-check.sh

lint-contracts:
	@./scripts/lint-contracts.sh

# Install source .scm files + compile .go files in place
install: install-src
	install -d $(DESTDIR)$(ccachedir)/hegel
	for f in $(MODULES); do \
		$(GUILD) compile -L $(DESTDIR)$(sitedir) \
		  -o $(DESTDIR)$(ccachedir)/$$f.go \
		  $(DESTDIR)$(sitedir)/$$f || true; \
	done
	$(GUILD) compile -L $(DESTDIR)$(sitedir) \
	  -o $(DESTDIR)$(ccachedir)/$(TOP_MODULE:.scm=.go) \
	  $(DESTDIR)$(sitedir)/$(TOP_MODULE) || true

# Install only source files (no compilation)
install-src:
	install -d $(DESTDIR)$(sitedir)/hegel
	install -m 644 $(SRC_DIR)/$(TOP_MODULE) $(DESTDIR)$(sitedir)/
	for f in $(MODULES); do \
		install -m 644 $(SRC_DIR)/$$f $(DESTDIR)$(sitedir)/$$f; \
	done

uninstall:
	rm -f $(DESTDIR)$(sitedir)/$(TOP_MODULE)
	rm -rf $(DESTDIR)$(sitedir)/hegel
	rm -f $(DESTDIR)$(ccachedir)/$(TOP_MODULE:.scm=.go)
	rm -rf $(DESTDIR)$(ccachedir)/hegel

tangle:
	emacs --batch --eval \
	  "(progn (require 'ob-tangle) \
	          (org-babel-tangle-file \"hegel-guile.org\"))"

clean:
	find . -name '*.go' -delete

help:
	@echo "Targets:"
	@echo "  compile        - Compile all modules to .go files"
	@echo "  test           - Run test suite"
	@echo "  check          - Run test suite (alias for test)"
	@echo "  check-verbose  - Run tests with per-file exit codes"
	@echo "  test-all       - Run all tests (alias for test)"
	@echo "  repl           - Start Guile REPL with load path"
	@echo "  lint           - Run all linters (docs + contracts)"
	@echo "  lint-docs      - Check documentation coverage"
	@echo "  lint-contracts - Check module contracts"
	@echo "  install        - Install to prefix (default: /usr/local)"
	@echo "  install-src    - Install source files only"
	@echo "  uninstall      - Remove installed files"
	@echo "  tangle         - Tangle from hegel-guile.org"
	@echo "  clean          - Remove compiled .go files"
	@echo "  help           - Show this help"
