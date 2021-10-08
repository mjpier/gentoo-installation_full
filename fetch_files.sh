#!/bin/bash

set -euo pipefail

function rmGPG {
    gpgconf --kill all
    rm -rf ~/.gnupg
}

pushd /mnt/gentoo

if [ -d ~/.gnupg ]; then
    # shellcheck disable=SC2088
    echo "~/.gnupg already exists. Aborting..."
    exit 1
fi

# fetch stage3 tarball
CURRENT_STAGE3="$(curl -fsSL --cert-status --proto '=https' --tlsv1.3 "https://ftp.tu-ilmenau.de/mirror/gentoo/releases/amd64/autobuilds/latest-stage3-amd64-hardened-openrc.txt" | grep -v "^#" | awk '{print $1}' | cut -d/ -f2)"
curl -fsSLO --cert-status --proto '=https' --tlsv1.3 "https://ftp.fau.de/gentoo/releases/amd64/autobuilds/current-stage3-amd64-hardened-openrc/${CURRENT_STAGE3}"
curl -fsSLO --cert-status --proto '=https' --tlsv1.3 "https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/releases/amd64/autobuilds/current-stage3-amd64-hardened-openrc/${CURRENT_STAGE3}.DIGESTS.asc"
gpg --keyserver hkps://keys.gentoo.org --recv-keys 0x13EBBDBEDE7A12775DFDB1BABB572E0E2D182910
echo "13EBBDBEDE7A12775DFDB1BABB572E0E2D182910:6:" | gpg --import-ownertrust
gpg --status-fd 1 --verify "${CURRENT_STAGE3##*/}.DIGESTS.asc" 2>/dev/null | grep "^\[GNUPG:\]" | awk '{print $2}' | grep -e "^GOODSIG$" -e "^VALIDSIG$" -e "^TRUST_ULTIMATE$" | sort | paste -d ' ' -s - | grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$"
grep -A1 "SHA512" "${CURRENT_STAGE3##*/}.DIGESTS.asc" | grep "${CURRENT_STAGE3##*/}$" | sha512sum -c

rmGPG

# fetch portage tarball
curl -fsSLO --cert-status --proto '=https' --tlsv1.3 "https://ftp.fau.de/gentoo/snapshots/portage-latest.tar.xz"
curl -fsSLO --cert-status --proto '=https' --tlsv1.3 "https://ftp-stud.hs-esslingen.de/pub/Mirrors/gentoo/snapshots/portage-latest.tar.xz.gpgsig"
gpg --keyserver hkps://keys.gentoo.org --recv-keys 0xDCD05B71EAB94199527F44ACDB6B8C1F96D8BF6D
echo "DCD05B71EAB94199527F44ACDB6B8C1F96D8BF6D:6:" | gpg --import-ownertrust
gpg --status-fd 1 --verify portage-latest.tar.xz.gpgsig portage-latest.tar.xz 2>/dev/null | grep "^\[GNUPG:\]" | awk '{print $2}' | grep -e "^GOODSIG$" -e "^VALIDSIG$" -e "^TRUST_ULTIMATE$" | sort | paste -d ' ' -s - | grep -q "^GOODSIG TRUST_ULTIMATE VALIDSIG$"

rmGPG

popd
