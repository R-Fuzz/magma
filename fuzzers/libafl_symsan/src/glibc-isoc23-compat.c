// Compatibility shim for the magma docker image's glibc (ubuntu:22.04 ->
// 2.35), which predates glibc 2.38's ISO C23 rename of the strto*/wcsto*/
// *scanf family to __isoc23_*.  symsan's prebuilt libcxx/build_taint
// archives (libcxx/build_taint/lib/*.a, committed to the symsan repo) are
// compiled on whatever host runs libcxx/rebuild.sh, and if that host's
// glibc is >= 2.38, libc++.a's locale.cpp.o unconditionally calls the
// renamed symbols -- e.g. std::istream::operator>>(unsigned long&) pulls in
// __num_get_unsigned_integral, which calls __isoc23_strtoull_l.  Those
// symbols don't exist in glibc 2.35 at all (not even as a compat version),
// so any target whose harness touches iostream formatted extraction (e.g.
// libtiff's tiff_read_rgba_fuzzer, via std::istringstream) fails to link
// inside the container with "undefined reference to `__isoc23_strtoull_l'"
// -- one target at a time, only once its code path happens to need it.
//
// instrument.sh compiles this alongside harness-proxy.c and archives it into
// the same FUZZER_LIB, so it is only pulled in (and only matters) for a
// program whose link actually leaves one of these symbols undefined.
//
// Only ever built inside the magma docker image, by the container's own
// ko-clang against the container's own glibc headers -- never by symsan's
// CMakeLists (which only precompiles harness-proxy.c, not this) and never on
// a dev host.  That is load-bearing: glibc's rename happens via an asm-label
// on the *declaration* of e.g. strtoull_l, so on a glibc >= 2.38 host the
// calls below would themselves compile to calls to __isoc23_strtoull_l --
// i.e. this file defining its own callees, infinite recursion at runtime
// instead of a link error. The #error turns that into a build failure if
// magma's base image is ever bumped past glibc 2.38.
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdlib.h>
#include <wchar.h>
#include <stdio.h>
#include <stdarg.h>
#include <locale.h>

#if defined(__GLIBC_USE) && __GLIBC_USE(C2X_STRTOL)
#error "this glibc already renames strto*/wcsto*/scanf to __isoc23_* -- the " \
       "forwarding calls below would recurse into themselves; see the " \
       "comment at the top of this file"
#endif

long __isoc23_strtol(const char *nptr, char **endptr, int base) {
    return strtol(nptr, endptr, base);
}
long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
    return strtoll(nptr, endptr, base);
}
long long __isoc23_strtoll_l(const char *nptr, char **endptr, int base,
                              locale_t loc) {
    return strtoll_l(nptr, endptr, base, loc);
}
unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base) {
    return strtoul(nptr, endptr, base);
}
unsigned long long __isoc23_strtoull(const char *nptr, char **endptr,
                                      int base) {
    return strtoull(nptr, endptr, base);
}
unsigned long long __isoc23_strtoull_l(const char *nptr, char **endptr,
                                        int base, locale_t loc) {
    return strtoull_l(nptr, endptr, base, loc);
}
long __isoc23_wcstol(const wchar_t *nptr, wchar_t **endptr, int base) {
    return wcstol(nptr, endptr, base);
}
long long __isoc23_wcstoll(const wchar_t *nptr, wchar_t **endptr, int base) {
    return wcstoll(nptr, endptr, base);
}
unsigned long __isoc23_wcstoul(const wchar_t *nptr, wchar_t **endptr,
                                int base) {
    return wcstoul(nptr, endptr, base);
}
unsigned long long __isoc23_wcstoull(const wchar_t *nptr, wchar_t **endptr,
                                      int base) {
    return wcstoull(nptr, endptr, base);
}
int __isoc23_sscanf(const char *str, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int r = vsscanf(str, format, ap);
    va_end(ap);
    return r;
}
int __isoc23_vsscanf(const char *str, const char *format, va_list ap) {
    return vsscanf(str, format, ap);
}
