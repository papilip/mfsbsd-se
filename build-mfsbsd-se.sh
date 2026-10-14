#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
#
# build-mfsbsd-se.sh — construit une image mfsBSD SE (« special edition » :
# avec base.txz et kernel.txz embarqués) pour une release FreeBSD donnée,
# comme le fait le projet mfsBSD (ci/ci.sh, cible build-se), quand le projet
# n'en publie pas (aucune image 15.1 au 14 octobre 2026) ou plus (FreeBSD 16).
#
# Lancé par le flux GitHub Actions du dépôt papilip/mfsbsd-se, dans une
# machine virtuelle FreeBSD de la version visée (voir README.adoc). À la
# main : en root sur une machine FreeBSD de la même majeure que l'image (le
# builder pkg.quimeo.net pour la branche 15) :
#
#   sh build-mfsbsd-se.sh 15.1 [RÉPERTOIRE_DE_SORTIE]
#
# Étapes :
#   1. sources de mfsBSD : clone de github.com/mmatuska/mfsbsd au commit
#      MFSBSD_REF (défaut ci-dessous : celui de l'étiquette v20260120-080439,
#      dernière publication du projet) ;
#   2. base.txz et kernel.txz de la release, depuis download.freebsd.org
#      (https), vérifiés par le MANIFEST de la release ;
#   3. make iso SE=1 ROOTHACK=1, comme le projet ;
#   4. dans RÉPERTOIRE_DE_SORTIE (défaut : /var/tmp/mfsbsd-se-<version>) :
#      l'image mfsbsd-se-<version>-RELEASE-amd64.iso et son empreinte
#      (fichier .sha256), puis les trois lignes à poser dans la
#      configuration beryl de la société (_defaults.yml).
#
# Publication : par le flux du dépôt (release `mfsbsd-se-<version>` de
# papilip/mfsbsd-se), ou à la main pour une image construite hors de GitHub.
#
# Variables : MFSBSD_REF (étiquette ou commit de mfsBSD), FREEBSD_MIRROR
# (défaut https://download.freebsd.org/releases), WORKDIR (défaut
# /var/tmp/mfsbsd-build).
set -eu

die() {
  echo "build-mfsbsd-se : $*" >&2
  exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] || die "usage : sh build-mfsbsd-se.sh X.Y [RÉPERTOIRE_DE_SORTIE]"
VERSION="$1"
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+$' || die "version X.Y attendue (ex. 15.1) : $VERSION"
RELEASE="$VERSION-RELEASE"
MAJOR="${VERSION%%.*}"
OUT="${2:-/var/tmp/mfsbsd-se-$VERSION}"

MFSBSD_REPO=https://github.com/mmatuska/mfsbsd.git
# Commit de l'étiquette v20260120-080439 (étiquette légère) : un commit ne
# bouge pas, une étiquette si.
MFSBSD_REF="${MFSBSD_REF:-83f2dbb507625e8f2b928670744667e14b6aed97}"
FREEBSD_MIRROR="${FREEBSD_MIRROR:-https://download.freebsd.org/releases}"
WORKDIR="${WORKDIR:-/var/tmp/mfsbsd-build}"
ARCH=amd64

[ "$(uname -s)" = FreeBSD ] || die "à lancer sur FreeBSD"
[ "$(id -u)" = 0 ] || die "à lancer en root (make iso monte des disques mémoire)"
host_major=$(uname -r | cut -d. -f1)
[ "$host_major" = "$MAJOR" ] ||
  die "machine en FreeBSD $host_major, image $VERSION : construisez sur une machine de la même majeure"
command -v git >/dev/null || die "git absent (pkg install git)"

ISO="mfsbsd-se-$RELEASE-$ARCH.iso"
SRC="$WORKDIR/mfsbsd"
DIST="$WORKDIR/dist-$RELEASE"
mkdir -p "$WORKDIR" "$DIST" "$OUT"

echo "== sources de mfsBSD ($MFSBSD_REF)"
if [ ! -d "$SRC/.git" ]; then
  git clone -q "$MFSBSD_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q --detach "$MFSBSD_REF"
echo "   commit $(git -C "$SRC" rev-parse HEAD)"

echo "== base.txz et kernel.txz de $RELEASE"
url="$FREEBSD_MIRROR/$ARCH/$RELEASE"
fetch -q -m -o "$DIST/MANIFEST" "$url/MANIFEST" || die "MANIFEST introuvable : $url (release publiée ?)"
for f in base.txz kernel.txz; do
  fetch -q -m -o "$DIST/$f" "$url/$f" || die "téléchargement impossible : $url/$f"
  want=$(awk -v f="$f" '$1 == f { print $2 }' "$DIST/MANIFEST")
  [ -n "$want" ] || die "$f absent du MANIFEST"
  got=$(sha256 -q "$DIST/$f")
  [ "$got" = "$want" ] || die "$f : empreinte $got, MANIFEST $want"
  echo "   $f vérifié"
done

echo "== construction de $ISO"
cd "$SRC"
if [ ! -x tools/roothack/roothack ]; then
  (cd tools/roothack && make -s depend && make -s)
fi
make -s clean
env TARGET=$ARCH TARGET_ARCH=$ARCH make iso RELEASE="$RELEASE" BASE="$DIST" ROOTHACK=1 SE=1
[ -s "$ISO" ] || die "image $ISO non produite"
mv -f "$ISO" "$OUT/$ISO"
make -s clean

cd "$OUT"
sum=$(sha256 -q "$ISO")
printf '%s  %s\n' "$sum" "$ISO" >"$ISO.sha256"

echo "== image prête : $OUT/$ISO"
echo "   sha256 $sum"
echo
echo "Après publication (release mfsbsd-se-$VERSION de papilip/mfsbsd-se), dans"
echo "_defaults.yml de la société dans la configuration beryl :"
echo "  mfsbsd_url: https://github.com/papilip/mfsbsd-se/releases/download/mfsbsd-se-$VERSION/$ISO"
echo "  mfsbsd_version: \"$VERSION\""
echo "  mfsbsd_sha256: $sum"
