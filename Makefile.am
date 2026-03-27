## Makefile.am — top-level automake input for hegel-guile

SUBDIRS = src

EXTRA_DIST =              \
  README.org              \
  CHANGELOG.org           \
  LICENSE                 \
  CLAUDE.md               \
  AGENTS.md               \
  Makefile.simple         \
  hegel-guile.org         \
  hegel-guile.el          \
  pyproject.toml          \
  conjectures.org         \
  conjectures-c10-c15.org \
  roadmap.org             \
  bin/health-check.sh     \
  examples/basic.scm      \
  examples/ledger.scm     \
  examples/lisp.scm       \
  examples/sicp.scm       \
  examples/todo.scm

# Test support: use Guile as the test compiler for .scm files
TEST_EXTENSIONS = .scm
SCM_LOG_COMPILER = $(GUILE)
AM_SCM_LOG_FLAGS = -L $(abs_top_srcdir)/src

TESTS =                            \
  tests/test-cbor.scm              \
  tests/test-channel.scm           \
  tests/test-crc32.scm             \
  tests/test-generators.scm        \
  tests/test-mux.scm               \
  tests/test-packet.scm            \
  tests/test-protocol.scm          \
  tests/test-server.scm            \
  tests/test-test-case.scm         \
  tests/test-test.scm

EXTRA_DIST +=                      \
  tests/test-cbor.scm              \
  tests/test-channel.scm           \
  tests/test-crc32.scm             \
  tests/test-generators.scm        \
  tests/test-mux.scm               \
  tests/test-packet.scm            \
  tests/test-protocol.scm          \
  tests/test-server.scm            \
  tests/test-test-case.scm         \
  tests/test-test.scm
