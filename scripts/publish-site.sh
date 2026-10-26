#!/usr/bin/env bash
#
# Web sitesini yayımlar: https://cnkndmr.github.io/deskmap/ adresi
# cnkndmr.github.io deposunun deskmap/ klasörüdür (kökte Jekyll yok, .nojekyll).
# Siteyi o taban adresle derler, klasörü yeniler, commit'ler ve push'lar.
#
#   make site-publish
#   PAGES_REPO=~/başka/klon make site-publish   # depo başka yerdeyse
#   NO_PUSH=1 make site-publish                 # yalnız yerel commit
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGES_REPO="${PAGES_REPO:-$HOME/Projects/kisisel/cnkndmr.github.io}"
SITE_URL="https://cnkndmr.github.io/deskmap/"

[[ -d "$PAGES_REPO/.git" ]] || { echo "No clone of cnkndmr.github.io at $PAGES_REPO (set PAGES_REPO)." >&2; exit 1; }
if [[ -n "$(git -C "$PAGES_REPO" status --porcelain)" ]]; then
  echo "$PAGES_REPO has uncommitted changes; commit or stash them first." >&2
  exit 1
fi
git -C "$PAGES_REPO" pull -q --ff-only

OUT="$(mktemp -d)/site"
SITE_URL="$SITE_URL" SITE_OUT="$OUT" node "$PROJECT_DIR/scripts/build-site.mjs" --strict

rm -rf "$PAGES_REPO/deskmap"
cp -R "$OUT" "$PAGES_REPO/deskmap"
rm -rf "$(dirname "$OUT")"

git -C "$PAGES_REPO" add -A deskmap
if git -C "$PAGES_REPO" diff --cached --quiet; then
  echo "Site unchanged."
  exit 0
fi
REV="$(git -C "$PROJECT_DIR" rev-parse --short HEAD)"
git -C "$PAGES_REPO" commit -qm "Deskmap site from $REV"
if [[ -z "${NO_PUSH:-}" ]]; then
  git -C "$PAGES_REPO" push -q
  echo "Published $SITE_URL (Deskmap $REV)."
else
  echo "Committed in $PAGES_REPO (not pushed)."
fi
