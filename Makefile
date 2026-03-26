# Makefile for hegel-guile

GUILD   ?= guild
GUILE   ?= guile3
SRC_DIR := src
TEST_DIR:= tests

# Compile all modules
.PHONY: compile test clean tangle

compile:
	$(GUILD) compile -L $(SRC_DIR) \
	  $(SRC_DIR)/hegel/crc32.scm \
	  $(SRC_DIR)/hegel/cbor.scm \
	  $(SRC_DIR)/hegel/packet.scm \
	  $(SRC_DIR)/hegel/channel.scm \
	  $(SRC_DIR)/hegel/protocol.scm \
	  $(SRC_DIR)/hegel/generators.scm \
	  $(SRC_DIR)/hegel/server.scm \
	  $(SRC_DIR)/hegel/test-case.scm \
	  $(SRC_DIR)/hegel/test.scm \
	  $(SRC_DIR)/hegel.scm

test: compile
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-cbor.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-crc32.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-packet.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-channel.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-protocol.scm
	$(GUILE) -L $(SRC_DIR) $(TEST_DIR)/test-generators.scm

tangle:
	emacs --batch --eval \
	  "(progn (require 'ob-tangle) \
	          (org-babel-tangle-file \"hegel-guile.org\"))"

clean:
	find . -name '*.go' -delete
	rm -f doc/architecture.mmd doc/protocol-flow.mmd
