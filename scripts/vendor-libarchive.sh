#!/usr/bin/env bash
# Vendors the pinned libarchive release into Packages/Archive/Sources/CArchive, keeping only the files that ZIP
# read/write and RAR read need. Rerun it to reproduce or review the vendored tree; bump VERSION and SHA256 to upgrade.
# Usage: scripts/vendor-libarchive.sh [path to an already-downloaded tarball]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=3.8.11
SHA256=900fe9fc7237c2b04f090f3c3648de8fe597525771f5035016537ce2d667d12b
URL="https://github.com/libarchive/libarchive/releases/download/v$VERSION/libarchive-$VERSION.tar.gz"
dest=Packages/Archive/Sources/CArchive

public_headers=(archive.h archive_entry.h)
sources=(
  archive_acl.c archive_check_magic.c archive_crc32.c archive_cryptor.c archive_entry.c archive_entry_sparse.c
  archive_entry_xattr.c archive_hmac.c archive_options.c archive_random.c archive_rb.c archive_read.c
  archive_read_add_passphrase.c archive_read_open_filename.c archive_string.c archive_string_sprintf.c
  archive_time.c archive_util.c archive_virtual.c archive_write.c archive_write_open_fd.c
  archive_write_open_filename.c archive_write_set_passphrase.c
  archive_ppmd8.c archive_read_support_format_zip.c archive_write_set_format_zip.c
  # RAR and RAR5, compiled but not exposed until CBR import needs them
  archive_blake2s_ref.c archive_blake2sp_ref.c archive_ppmd7.c archive_read_support_format_rar.c
  archive_read_support_format_rar5.c
)
private_headers=(
  archive_acl_private.h archive_blake2.h archive_blake2_impl.h archive_cryptor_private.h archive_digest_private.h
  archive_endian.h archive_entry_locale.h archive_entry_private.h archive_hmac_private.h archive_integer.h
  archive_options_private.h archive_platform.h archive_platform_stat.h archive_ppmd7_private.h
  archive_ppmd8_private.h archive_ppmd_private.h archive_private.h archive_random_private.h archive_rb.h
  archive_read_private.h archive_string.h archive_string_composition.h archive_time_private.h
  archive_write_private.h archive_write_set_format_private.h
)

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tarball="${1:-$work/libarchive-$VERSION.tar.gz}"
[[ -n "${1:-}" ]] || curl -fsSL -o "$tarball" "$URL"
echo "$SHA256  $tarball" | shasum -a 256 -c -
tar -xzf "$tarball" -C "$work"
src="$work/libarchive-$VERSION"

rm -rf "$dest/include" "$dest/libarchive" "$dest/COPYING"
mkdir -p "$dest/include" "$dest/libarchive"
for f in "${public_headers[@]}"; do cp "$src/libarchive/$f" "$dest/include/"; done
for f in "${sources[@]}" "${private_headers[@]}"; do cp "$src/libarchive/$f" "$dest/libarchive/"; done
# The ZIP writer needs one helper from this file, whose format table would pull in every other writer.
awk '/^\/\* A table that maps format codes to functions/ {skip=1} /^void$/ {skip=0} !skip' \
  "$src/libarchive/archive_write_set_format.c" > "$dest/libarchive/archive_write_set_format.c"
cp "$src/COPYING" "$dest/COPYING"
echo "Vendored libarchive $VERSION into $dest."
