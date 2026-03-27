## src/Makefile.am — install top-level hegel.scm module

SUBDIRS = hegel

moddir = $(guilesitedir)
godir  = $(guilesite_ccachedir)

nobase_mod_DATA = hegel.scm

GOBJECTS = hegel.go

nobase_go_DATA = $(GOBJECTS)

hegel.go: hegel.scm hegel/cbor.go hegel/protocol.go hegel/generators.go \
           hegel/server.go hegel/test-case.go hegel/test.go            \
           hegel/packet.go hegel/mux.go hegel/channel.go hegel/crc32.go
	GUILE_LOAD_PATH=$(srcdir):$(builddir):$$GUILE_LOAD_PATH \
	GUILE_LOAD_COMPILED_PATH=$(builddir):$$GUILE_LOAD_COMPILED_PATH \
	$(GUILD) compile -L $(srcdir) -L $(builddir) -o $@ $(srcdir)/$<

CLEANFILES = $(GOBJECTS)
EXTRA_DIST = hegel.scm
