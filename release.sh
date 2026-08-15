#!/usr/bin/env bash
#
# Cut a new release of the Plazza Driver Status extension.
#
#   ./release.sh [path-to-extension-source]
#
# Bump "version" in the extension's manifest.json first; everything else
# here is derived from it. Run from this repo's directory.
#
# Why a script rather than the steps in the README: every manual step is a
# chance to ship something that breaks force-install SILENTLY — signing with
# the wrong key (changes the extension ID, so enrolled browsers stop
# recognising it), forgetting to update update.xml (the new .crx is in the
# repo but nothing points at it), or updating one feed variant and not the
# other. This checks for all three rather than trusting anyone to remember.

set -euo pipefail

SRC="${1:-$HOME/Downloads/plazza-driver-status-extension}"
DIST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="$HOME/Downloads/plazza-extension-signing-key-v2.pem"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# The ID every enrolled browser has pinned. If a build ever produces a
# different one, that build must NOT ship: Chrome would treat it as an
# unrelated extension and the force-install policy would quietly stop
# matching. This is the single most important check in this script.
EXPECTED_ID="jcoackohkdbhkojionoojgonlgkddckk"

PAGES_BASE="https://plazza-in.github.io/driver-status-extension-dist"
JSDELIVR_BASE="https://cdn.jsdelivr.net/gh/Plazza-in/driver-status-extension-dist@main"

die() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$SRC" ]  || die "extension source not found at $SRC"
[ -f "$KEY" ]  || die "signing key not found at $KEY — without it, a build gets a different extension ID and force-install breaks for everyone"
[ -x "$CHROME" ] || die "Chrome not found at $CHROME"

VERSION=$(python3 -c "import json;print(json.load(open('$SRC/manifest.json'))['version'])")
echo "==> Releasing v$VERSION"

CRX_NAME="plazza-driver-status-v$VERSION.crx"
if [ -f "$DIST/$CRX_NAME" ]; then
  die "$CRX_NAME already exists — bump \"version\" in $SRC/manifest.json first (Chrome ignores a feed whose version isn't strictly newer than what's installed)"
fi

# --- syntax-check before packing, not after shipping -----------------------
for f in background.js sidepanel.js content-freshchat.js; do
  node --check "$SRC/$f" >/dev/null || die "$f has a syntax error"
done
python3 -c "import json;json.load(open('$SRC/manifest.json'))" || die "manifest.json is not valid JSON"
echo "    syntax OK"

# --- stage only the runtime files -----------------------------------------
STAGE="$(mktemp -d)/ext"
mkdir -p "$STAGE/icons"
cp "$SRC/manifest.json" "$SRC/background.js" "$SRC/content-freshchat.js" \
   "$SRC/sidepanel.html" "$SRC/sidepanel.js" "$SRC/sidepanel.css" "$STAGE/"
cp "$SRC/icons/"*.png "$STAGE/icons/"

# --- pack (Chrome needs PKCS#8; the stored key is PKCS#1) ------------------
WORK="$(mktemp -d)"
# Any exit from here on shreds the temp private-key copy — including a
# failure partway through, which is exactly when it would otherwise be left
# lying around.
cleanup() {
  [ -f "$WORK/key-pkcs8.pem" ] && { shred -u "$WORK/key-pkcs8.pem" 2>/dev/null || rm -f "$WORK/key-pkcs8.pem"; }
  rm -rf "$WORK"
}
trap cleanup EXIT

openssl pkcs8 -topk8 -nocrypt -in "$KEY" -out "$WORK/key-pkcs8.pem"
"$CHROME" --pack-extension="$STAGE" --pack-extension-key="$WORK/key-pkcs8.pem" \
          --user-data-dir="$WORK/profile" --headless --no-first-run >/dev/null 2>&1 || true
[ -f "$STAGE.crx" ] || die "Chrome did not produce a .crx"

# --- verify the ID matches what enrolled browsers expect -------------------
ACTUAL_ID=$(openssl rsa -in "$KEY" -pubout -outform DER 2>/dev/null | python3 -c "
import hashlib,sys
d=hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:32]
print(''.join(chr(ord('a')+int(c,16)) for c in d))
")
[ "$ACTUAL_ID" = "$EXPECTED_ID" ] || die "signing key produces extension ID $ACTUAL_ID, expected $EXPECTED_ID — WRONG KEY. Shipping this would silently break force-install for every agent."
echo "    extension ID verified: $ACTUAL_ID"

mv "$STAGE.crx" "$DIST/$CRX_NAME"
echo "    packed $CRX_NAME ($(wc -c < "$DIST/$CRX_NAME" | tr -d ' ') bytes)"

# --- regenerate every feed variant from one source of truth ---------------
# Two feeds on independent domains so switching hosts is a policy edit, not
# a scramble, if one is ever blocked (raw.githubusercontent.com already was,
# 2026-08-14). Generated together so they can't drift out of sync.
write_feed() {
  cat > "$DIST/$1" <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$EXPECTED_ID'>
    <updatecheck codebase='$2/$CRX_NAME' version='$VERSION' />
  </app>
</gupdate>
EOF
}
write_feed "update.xml" "$PAGES_BASE"
write_feed "update-jsdelivr.xml" "$JSDELIVR_BASE"
echo "    regenerated update.xml + update-jsdelivr.xml -> v$VERSION"

echo
echo "==> Ready. Review, then:"
echo "      cd $DIST && git add -A && git commit -m 'Release v$VERSION' && git push"
echo
echo "    After pushing, GitHub Pages takes ~1 min to rebuild. Verify with:"
echo "      curl -s '$PAGES_BASE/update.xml'"
