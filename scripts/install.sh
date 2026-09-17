#!/usr/bin/env bash
# Install (or upgrade to) the latest release of the osmflat toolchain.
#
#   install.sh              # all four tools
#   install.sh render       # just one
#
# Normally you don't need this: render.sh / taginfo.sh / build-archive.sh each
# install what they need on first use. Run it to pre-warm, or to upgrade after
# a new release.
#
# Installs under $OSMFLAT_HOME (default ${XDG_DATA_HOME:-~/.local/share}/osmflat).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/osmflat-env.sh"

tools=("$@")
[ ${#tools[@]} -eq 0 ] && tools=(render osmflat-taginfo osmflatc osmflat-extc)

for tool in "${tools[@]}"; do
    osmflat_install "$tool"
done

echo
echo "installed in $OSMFLAT_BINDIR:"
ls -l "$OSMFLAT_BINDIR"
