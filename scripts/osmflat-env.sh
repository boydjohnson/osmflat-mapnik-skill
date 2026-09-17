#!/usr/bin/env bash
# Shared bootstrap for the osmflat toolchain. Sourced by render.sh, taginfo.sh
# and build-archive.sh; also runnable directly (see install.sh).
#
# Resolves four binaries, installing the latest GitHub release on first use:
#
#   render            boydjohnson/osmflat-mapnik-plugin   style.xml -> PNG
#   osmflat-taginfo   boydjohnson/osmflat-taginfo         tag introspection
#   osmflatc          boydjohnson/osmflat-rs              .osm.pbf -> .osm.flat
#   osmflat-extc      boydjohnson/osmflat-ext             .osm.flat -> .ext sidecar
#
# Resolution order per tool: $OSMFLAT_BIN_<TOOL> override, then $PATH, then the
# managed install dir, then download. So a local dev build on PATH always wins.
#
# Env:
#   OSMFLAT_HOME      install root  [${XDG_DATA_HOME:-~/.local/share}/osmflat]
#   OSMFLAT_ARCHIVE   osmflat archive dir (required by render/taginfo)
#   OSMFLAT_EXT       Ext sidecar dir     [guessed from the archive name]
#   GITHUB_TOKEN      raises the GitHub API rate limit (optional)

set -euo pipefail

OSMFLAT_HOME="${OSMFLAT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/osmflat}"
OSMFLAT_BINDIR="$OSMFLAT_HOME/bin"
OSMFLAT_PKGDIR="$OSMFLAT_HOME/pkg"

osmflat_die() { echo "osmflat: $*" >&2; exit 1; }
osmflat_log() { echo "osmflat: $*" >&2; }

# ---------------------------------------------------------------- platform ---

_osmflat_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        *)      osmflat_die "unsupported OS $(uname -s); no prebuilt releases" ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) arch=aarch64 ;;
        x86_64|amd64)  arch=x86_64 ;;
        *)             osmflat_die "unsupported CPU $(uname -m); no prebuilt releases" ;;
    esac
    echo "$os/$arch"
}

_osmflat_repo() {
    case "$1" in
        render)          echo boydjohnson/osmflat-mapnik-plugin ;;
        osmflat-taginfo) echo boydjohnson/osmflat-taginfo ;;
        osmflatc)        echo boydjohnson/osmflat-rs ;;
        osmflat-extc)    echo boydjohnson/osmflat-ext ;;
        *)               osmflat_die "unknown tool '$1'" ;;
    esac
}

# Release target triples are NOT uniform across the four repos (gnu vs musl,
# with vs without the -unknown- vendor field), so they are mapped per tool.
_osmflat_triple() {
    case "$1:$(_osmflat_platform)" in
        *:darwin/aarch64)               echo aarch64-apple-darwin ;;
        osmflatc:linux/x86_64)          echo x86_64-unknown-linux-gnu ;;
        osmflat-extc:linux/x86_64)      echo x86_64-unknown-linux-gnu ;;
        osmflat-taginfo:linux/x86_64)   echo x86_64-unknown-linux-musl ;;
        render:linux/x86_64)            echo x86_64-linux-musl ;;
        render:linux/aarch64)           echo aarch64-linux-musl ;;
        *) osmflat_die "$1 has no release build for $(_osmflat_platform).
Published targets: see https://github.com/$(_osmflat_repo "$1")/releases/latest
Build from source, then put the binary on PATH or set OSMFLAT_BIN_$(_osmflat_varname "$1")." ;;
    esac
}

_osmflat_varname() { echo "$1" | tr 'a-z-' 'A-Z_'; }

# ----------------------------------------------------------------- install ---

_osmflat_curl() {
    local args=(-fsSL)
    [ -n "${GITHUB_TOKEN:-}" ] && args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
    curl "${args[@]}" "$@"
}

# Asset download URLs of a repo's latest release, one per line.
_osmflat_latest_assets() {
    _osmflat_curl -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/$1/releases/latest" \
        | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"\(https[^"]*\)".*/\1/'
}

_osmflat_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else osmflat_die "need sha256sum or shasum to verify downloads"
    fi
}

# osmflat_install <tool> -- download, verify, unpack the latest release.
osmflat_install() {
    local tool="$1" repo triple assets tarurl sumurl tarball dir want got
    repo="$(_osmflat_repo "$tool")"
    triple="$(_osmflat_triple "$tool")"

    command -v curl >/dev/null 2>&1 || osmflat_die "curl is required to install $tool"
    command -v tar  >/dev/null 2>&1 || osmflat_die "tar is required to install $tool"

    osmflat_log "resolving latest $repo release..."
    assets="$(_osmflat_latest_assets "$repo")" \
        || osmflat_die "could not reach the GitHub API for $repo (rate limited? set GITHUB_TOKEN)"

    tarurl="$(printf '%s\n' "$assets" | grep -- "-$triple\.tar\.gz\$" | head -1)"
    sumurl="$(printf '%s\n' "$assets" | grep -- '/SHA256SUMS$' | head -1)"
    [ -n "$tarurl" ] || osmflat_die "latest $repo release has no asset for $triple"
    [ -n "$sumurl" ] || osmflat_die "latest $repo release has no SHA256SUMS"

    tarball="${tarurl##*/}"
    dir="${tarball%.tar.gz}"

    # Deliberately not `local`: the cleanup trap fires after locals are gone,
    # and under `set -u` a stale reference aborts and swallows the real error.
    _osmflat_tmp="$(mktemp -d)"
    trap 'rm -rf "${_osmflat_tmp:-}"' RETURN EXIT

    osmflat_log "downloading $tarball"
    _osmflat_curl --progress-bar -o "$_osmflat_tmp/$tarball" "$tarurl" \
        || osmflat_die "download failed: $tarurl"
    _osmflat_curl -o "$_osmflat_tmp/SHA256SUMS" "$sumurl" \
        || osmflat_die "download failed: $sumurl"

    want="$(grep -E "[ *]$tarball\$" "$_osmflat_tmp/SHA256SUMS" | awk '{print $1}' | head -1)"
    [ -n "$want" ] || osmflat_die "$tarball is not listed in SHA256SUMS"
    got="$(_osmflat_sha256 "$_osmflat_tmp/$tarball")"
    [ "$want" = "$got" ] || osmflat_die "checksum mismatch for $tarball
  expected $want
  got      $got
Refusing to install. Re-run, or report it at https://github.com/$repo/issues"

    tar xzf "$_osmflat_tmp/$tarball" -C "$_osmflat_tmp"
    [ -d "$_osmflat_tmp/$dir" ] || osmflat_die "$tarball did not unpack to $dir/"
    [ -x "$_osmflat_tmp/$dir/$tool" ] || osmflat_die "$tarball contains no $tool binary"

    mkdir -p "$OSMFLAT_PKGDIR" "$OSMFLAT_BINDIR"
    rm -rf "${OSMFLAT_PKGDIR:?}/$dir"
    mv "$_osmflat_tmp/$dir" "$OSMFLAT_PKGDIR/$dir"
    ln -sfn "../pkg/$dir/$tool" "$OSMFLAT_BINDIR/$tool"

    osmflat_log "installed $tool -> $OSMFLAT_PKGDIR/$dir"
}

# osmflat_need <tool> -- echo an executable path, installing on first use.
osmflat_need() {
    local tool="$1" override path
    override="OSMFLAT_BIN_$(_osmflat_varname "$tool")"
    if [ -n "${!override:-}" ]; then
        [ -x "${!override}" ] || osmflat_die "$override=${!override} is not executable"
        echo "${!override}"; return
    fi
    if path="$(PATH="$PATH:$OSMFLAT_BINDIR" command -v "$tool" 2>/dev/null)"; then
        echo "$path"; return
    fi
    osmflat_install "$tool" >&2
    path="$OSMFLAT_BINDIR/$tool"
    [ -x "$path" ] || osmflat_die "install of $tool did not produce $path"
    echo "$path"
}

# Fonts ship beside the packaged render binary; mapnik needs an explicit dir
# when render is reached through the bin/ symlink.
osmflat_font_dir() {
    local render="$1" dir target
    [ -n "${MAPNIK_FONT_DIR:-}" ] && { echo "$MAPNIK_FONT_DIR"; return 0; }
    dir="$(cd "$(dirname "$render")" && pwd)"
    target="$(readlink "$render" 2>/dev/null || true)"
    if [ -n "$target" ]; then
        # A symlink target is relative to the link's own directory, not $PWD.
        case "$target" in
            /*) dir="$(cd "$(dirname "$target")" && pwd)" ;;
            *)  dir="$(cd "$dir/$(dirname "$target")" && pwd)" ;;
        esac
    fi
    [ -d "$dir/fonts" ] && echo "$dir/fonts" || true
}

# osmflat_version <path> -- the bare version string, e.g. 0.300.0
# Reads stderr too: older osmflatc builds print --version there, and discarding
# it made this return empty, which silently defeated the check below.
# Only a dotted-numeric field counts: a missing or broken binary prints an
# error whose last word ("directory", "found") would otherwise pass as a version.
osmflat_version() {
    "$1" --version 2>&1 | awk 'NR==1{v=$NF; if (v ~ /^v?[0-9]+(\.[0-9]+)+$/) {sub(/^v/,"",v); print v}}'
}

# osmflatc and osmflat-extc share a flatdata schema and are released in
# lockstep, so a mismatch produces an unreadable multi-hundred-line schema diff
# from deep inside the sidecar build. Catch it up front.
#
# This is easy to hit precisely because PATH beats the managed install dir: a
# forgotten `cargo install osmflatc` from years ago silently shadows the
# release. Deliberate dev builds are the point of that ordering, so this warns
# with the real paths rather than overriding the choice.
osmflat_check_versions() {
    local a="$1" b="$2" va vb
    [ -n "${OSMFLAT_SKIP_VERSION_CHECK:-}" ] && return 0
    va="$(osmflat_version "$a")"; vb="$(osmflat_version "$b")"
    # Explicit if, not an && / || chain: under `set -e` a false chain used as a
    # statement exits the shell before the error below is ever reached.
    if [ "$va" = "$vb" ]; then
        return 0
    fi
    # An undeterminable version is not a pass: warn and continue rather than
    # either blocking a custom build or pretending the pair agrees.
    if [ -z "$va" ] || [ -z "$vb" ]; then
        osmflat_log "warning: could not read a version from ${a##*/} (${va:-?}) or ${b##*/} (${vb:-?});"
        osmflat_log "  skipping the compatibility check. A schema mismatch will surface as a"
        osmflat_log "  large WrongSignature diff during the sidecar build."
        return 0
    fi
    osmflat_die "version mismatch between the archive and sidecar compilers:
  osmflatc      $va   $a
  osmflat-extc  $vb   $b
They must agree on the flatdata schema; mixing them fails with a large
WrongSignature schema diff partway through the build.

A binary on PATH takes precedence over the managed install, so a stale
\`cargo install\` is the usual cause. Force the managed release with:
  OSMFLAT_BIN_OSMFLATC=$OSMFLAT_BINDIR/osmflatc \\
  OSMFLAT_BIN_OSMFLAT_EXTC=$OSMFLAT_BINDIR/osmflat-extc scripts/build-archive.sh ...
or upgrade/remove the stale one. Set OSMFLAT_SKIP_VERSION_CHECK=1 to override."
}

# -------------------------------------------------------------------- data ---

# The archive to render/introspect. Explicit env wins; otherwise a lone *.flat
# under $OSMFLAT_HOME/data is used.
osmflat_archive() {
    local found
    if [ -n "${OSMFLAT_ARCHIVE:-}" ]; then
        [ -d "$OSMFLAT_ARCHIVE" ] || osmflat_die "OSMFLAT_ARCHIVE=$OSMFLAT_ARCHIVE is not a directory"
        echo "$OSMFLAT_ARCHIVE"; return
    fi
    found=$(find "$OSMFLAT_HOME/data" -maxdepth 1 -type d -name '*.flat' 2>/dev/null || true)
    if [ -n "$found" ] && [ "$(printf '%s\n' "$found" | wc -l | tr -d ' ')" = 1 ]; then
        echo "$found"; return
    fi
    osmflat_die "no osmflat archive. Set OSMFLAT_ARCHIVE=/path/to/area.osm.flat
Build one from an .osm.pbf extract (e.g. from geofabrik.de) with:
  scripts/build-archive.sh /path/to/area.osm.pbf"
}

# The Ext sidecar. Naming is not fully consistent in the wild, so try the
# common spellings before giving up.
osmflat_ext() {
    local archive="$1" c
    if [ -n "${OSMFLAT_EXT:-}" ]; then echo "$OSMFLAT_EXT"; return; fi
    for c in "${archive%.flat}.ext" "$archive.ext" "${archive%.osm.flat}.ext" \
             "${archive%.flat}flat.ext"; do
        [ -d "$c" ] && { echo "$c"; return; }
    done
    return 1
}
