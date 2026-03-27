dnl configure.ac — GNU Autotools configuration for hegel-guile
dnl
dnl Usage:
dnl   autoreconf -vif
dnl   ./configure
dnl   make
dnl   make install
dnl   make dist

AC_INIT([hegel-guile], [0.7.1],
        [https://github.com/dsp-dr/hegel-guile/issues],
        [hegel-guile],
        [https://github.com/dsp-dr/hegel-guile])

AC_CONFIG_AUX_DIR([build-aux])
AM_INIT_AUTOMAKE([foreign -Wall -Werror])

GUILE_PKG([3.0])
GUILE_PROGS
GUILE_SITE_DIR

dnl Allow overriding install directories:
dnl   ./configure guilesitedir=/custom/path guilesite_ccachedir=/custom/go
AC_ARG_VAR([guilesitedir],
           [directory for installing Guile source modules
            (default: GUILE_SITE)])
AC_ARG_VAR([guilesite_ccachedir],
           [directory for installing compiled Guile modules
            (default: GUILE_SITE_CCACHE)])

AS_IF([test "x$guilesitedir" = x], [guilesitedir="$GUILE_SITE"])
AS_IF([test "x$guilesite_ccachedir" = x],
      [guilesite_ccachedir="$GUILE_SITE_CCACHE"])

AC_SUBST([guilesitedir])
AC_SUBST([guilesite_ccachedir])

AC_CONFIG_FILES([
  Makefile
  src/Makefile
  src/hegel/Makefile
])

AC_OUTPUT
