/*
 * Hand-written libarchive configuration for Apple platforms (macOS 15+, iOS 18+, iOS Simulator), replacing the
 * config.h that libarchive's configure step would generate. Only what the vendored ZIP and RAR code needs is set.
 * zlib is the only library linked; bzip2, LZMA, zstd, LZ4, iconv, ACL and xattr support are left out.
 */
#ifndef TSUZURI_LIBARCHIVE_CONFIG_H
#define TSUZURI_LIBARCHIVE_CONFIG_H

/* Xcode builds package C targets with -Wshorten-64-to-32, which upstream libarchive does not follow. */
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

#define HAVE_ZLIB_H 1

#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIMITS_H 1
#define HAVE_PTHREAD_H 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_TIME_H 1
#define HAVE_UNISTD_H 1
#define HAVE_WCHAR_H 1

#define HAVE_ARC4RANDOM_BUF 1
#define HAVE_FCNTL 1
#define HAVE_LOCALTIME_R 1
#define HAVE_MBRTOWC 1
#define HAVE_SYSCONF 1
#define HAVE_WCRTOMB 1
#define HAVE_WCSLEN 1
#define HAVE_WCTOMB 1
#define HAVE_WMEMCMP 1
#define HAVE_WMEMCPY 1
#define HAVE_WMEMMOVE 1

#define HAVE_DECL_INT32_MAX 1
#define HAVE_DECL_INT32_MIN 1
#define HAVE_DECL_INT64_MAX 1
#define HAVE_DECL_INT64_MIN 1
#define HAVE_DECL_INTMAX_MAX 1
#define HAVE_DECL_INTMAX_MIN 1
#define HAVE_DECL_SIZE_MAX 1
#define HAVE_DECL_SSIZE_MAX 1
#define HAVE_DECL_UINT32_MAX 1
#define HAVE_DECL_UINT64_MAX 1
#define HAVE_DECL_UINTMAX_MAX 1
#define SIZEOF_INT 4
#define SIZEOF_LONG 8

/*
 * libarchive converts entry names to the process locale's charset, but apps run in the C locale, whose charset is
 * US-ASCII, so a non-ASCII name in a ZIP flagged UTF-8 would fail to convert and read as no name at all. Reporting
 * UTF-8 lets such names through and makes the writer flag non-ASCII names as UTF-8. HAVE_LANGINFO_H stays unset
 * so that <langinfo.h> never meets this macro.
 */
#define HAVE_NL_LANGINFO 1
#define CODESET 0
#define nl_langinfo(item) "UTF-8"

#define HAVE_EFTYPE 1
#define HAVE_EILSEQ 1

#endif /* TSUZURI_LIBARCHIVE_CONFIG_H */
