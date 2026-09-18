#!/usr/bin/env bash
# Install (or upgrade to) the latest release of the osmflat toolchain.
#
#   install.sh --info               # show what would be downloaded; fetch nothing
#   install.sh --info render        # ...for one tool
#   install.sh                      # install all four tools
#   install.sh render               # install one
#
# This is the only way the binaries get installed: render.sh, taginfo.sh and
# build-archive.sh stop and point here when a tool is missing, so the user can
# agree first. Show them `--info` before running it. (OSMFLAT_AUTO_INSTALL=1
# restores install-on-first-use for people who have opted in.)
#
# Installs under $OSMFLAT_HOME (default ${XDG_DATA_HOME:-~/.local/share}/osmflat):
# no sudo, nothing written outside that directory, no PATH or profile changes.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

INFO=0
if [ "${1:-}" = "--info" ]; then INFO=1; shift; fi

tools=("$@")
[ ${#tools[@]} -eq 0 ] && tools=(render osmflat-taginfo osmflatc osmflat-extc)

if [ "$INFO" = 1 ]; then
    for tool in "${tools[@]}"; do
        osmflat_plan "$tool"
        echo
    done
    echo "Nothing downloaded. Install with: scripts/install.sh ${*:-}"
    exit 0
fi

for tool in "${tools[@]}"; do
    osmflat_install "$tool"
done

echo
echo "installed in $OSMFLAT_BINDIR:"
ls -l "$OSMFLAT_BINDIR"
