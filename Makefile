# Makefile for hegel-guile

GUILD   ?= guild
GUILE   ?= guile
SRC_DIR := src
TEST_DIR:= tests

.PHONY: compile test test-all repl clean tangle

compile:
	$(GUILD) compile -L $(SRC_DIR) \
	  $(SRC_DIR)/hegel/crc32.scm \
	  $(SRC_DIR)/hegel/cbor.scm \
	  $(SRC_DIR)/hegel/packet.scm \
	  $(SRC_DIR)/hegel/mux.scm \
	  $(SRC_DIR)/hegel/channel.scm \
	  $(SRC_DIR)/hegel/protocol.scm \
	  $(SRC_DIR)/hegel/generators.scm \
	  $(SRC_DIR)/hegel/server.scm \
	  $(SRC_DIR)/hegel/test-case.scm \
	  $(SRC_DIR)/hegel/test.scm \
	  $(SRC_DIR)/hegel.scm

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
