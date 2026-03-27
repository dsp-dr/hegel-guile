## src/hegel/Makefile.am — install hegel/* submodules

moddir = $(guilesitedir)/hegel
godir  = $(guilesite_ccachedir)/hegel

SOURCES =         \
  crc32.scm       \
  cbor.scm        \
  packet.scm      \
  mux.scm         \
  channel.scm     \
  protocol.scm    \
  generators.scm  \
  server.scm      \
  test-case.scm   \
  test.scm

mod_DATA = $(SOURCES)

GOBJECTS = $(SOURCES:.scm=.go)

go_DATA = $(GOBJECTS)

# Compilation order matters: dependencies first.
# guild compile needs to find sibling modules.
GUILE_COMPILE_ENV =                                             \
  GUILE_LOAD_PATH=$(top_srcdir)/src:$(top_builddir)/src:$$GUILE_LOAD_PATH \
  GUILE_LOAD_COMPILED_PATH=$(top_builddir)/src:$$GUILE_LOAD_COMPILED_PATH

GUILD_COMPILE = $(GUILE_COMPILE_ENV) $(GUILD) compile          \
  -L $(top_srcdir)/src -L $(top_builddir)/src

# Each .go depends on its .scm.
# Declare inter-module dependencies so parallel make works.
crc32.go: crc32.scm
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

cbor.go: cbor.scm
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

packet.go: packet.scm crc32.go cbor.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

mux.go: mux.scm packet.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

channel.go: channel.scm mux.go cbor.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

protocol.go: protocol.scm cbor.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

generators.go: generators.scm
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

server.go: server.scm protocol.go cbor.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

test-case.go: test-case.scm protocol.go cbor.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

test.go: test.scm test-case.go server.go protocol.go cbor.go generators.go
	$(GUILD_COMPILE) -o $@ $(srcdir)/$<

CLEANFILES = $(GOBJECTS)
EXTRA_DIST = $(SOURCES)
