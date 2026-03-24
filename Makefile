# Makefile for hegel-guile

GUILD   ?= guild
GUILE   ?= guile3
SRC_DIR := src
TEST_DIR:= tests

# Compile all modules
.PHONY: compile test clean tangle

compile:
	find $(SRC_DIR) -name '*.scm' | xargs -I{} $(GUILD) compile {}

test: compile
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-cbor.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-protocol.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-generators.scm

tangle:
	emacs --batch --eval \
	  "(progn (require 'ob-tangle) \
	          (org-babel-tangle-file \"hegel-guile.org\"))"

clean:
	find . -name '*.go' -delete
	rm -f doc/architecture.mmd doc/protocol-flow.mmd
