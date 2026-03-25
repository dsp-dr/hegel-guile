# Makefile for hegel-guile

GUILD   ?= guild3
GUILE   ?= guile3
SRC_DIR := src
TEST_DIR:= tests

# Compile all modules
.PHONY: compile test test-all repl clean tangle

compile:
	@find $(SRC_DIR) -name '*.scm' | while read f; do \
		$(GUILD) compile -L $(SRC_DIR) "$$f" || true; \
	done

test: compile
	@for f in $(TEST_DIR)/test-*.scm; do \
		echo "=== Running $$f ==="; \
		$(GUILE) -L $(SRC_DIR) "$$f" || exit 1; \
	done

test-all: test

repl:
	$(GUILE) -L $(SRC_DIR)

tangle:
	emacs --batch --eval \
	  "(progn (require 'ob-tangle) \
	          (org-babel-tangle-file \"hegel-guile.org\"))"

clean:
	find . -name '*.go' -delete
	rm -f doc/architecture.mmd doc/protocol-flow.mmd
