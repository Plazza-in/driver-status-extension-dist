#!/usr/bin/env bash
#
# Which update feeds are reachable from THIS machine/network, and what
# version does each serve?
#
#   ./check-mirrors.sh
#
# Run this when someone reports the extension is stuck on an old version, or
# when the side panel shows its "auto-updates appear stuck" banner. It tells
# you which host to point the Workspace policy at, and prints the exact
# string to paste.
#
# Run it from an affected agent's machine when you can — a mirror reachable
# from your laptop may still be blocked on theirs, and theirs is the network
# that matters.

set -uo pipefail

ID="ijocfdgbkehhnbhpoppeeoelegfildde"

# label|feed url
MIRRORS=(
  "GitHub Pages |https://plazza-in.github.io/driver-status-extension-dist/update.xml"
  "jsDelivr CDN |https://cdn.jsdelivr.net/gh/Plazza-in/driver-status-extension-dist@main/update-jsdelivr.xml"
  "GitHub raw   |https://raw.githubusercontent.com/Plazza-in/driver-status-extension-dist/main/update.xml"
)

echo "Checking update feeds (10s timeout each)..."
echo

BEST=""
for entry in "${MIRRORS[@]}"; do
  LABEL="${entry%%|*}"
  URL="${entry##*|}"

  BODY=$(curl -s --max-time 10 "$URL?t=$(date +%s)" 2>/dev/null)
  CODE=$?

  if [ $CODE -ne 0 ] || [ -z "$BODY" ]; then
    # Exit 28 is curl's timeout — the signature of a silent hostname block
    # (the connection never completes) rather than a server saying no.
    [ $CODE -eq 28 ] && WHY="timed out (host may be blocked on this network)" || WHY="unreachable (curl exit $CODE)"
    printf "  %s  DOWN  — %s\n" "$LABEL" "$WHY"
    continue
  fi

  # Anchored on <updatecheck: the XML declaration also contains a
  # version='1.0', and grepping loosely reports that instead.
  VER=$(printf '%s' "$BODY" | grep -o "<updatecheck[^>]*version='[0-9.]*'" | grep -o "[0-9][0-9.]*" | tail -1)
  if [ -z "$VER" ]; then
    printf "  %s  BAD   — reachable but no version found (not our feed?)\n" "$LABEL"
    continue
  fi

  printf "  %s  OK    — serving v%s\n" "$LABEL" "$VER"
  [ -z "$BEST" ] && BEST="$URL"
done

echo
if [ -z "$BEST" ]; then
  echo "No mirror is reachable from this machine."
  echo
  echo "If this machine's network is the problem, updates are stuck only here."
  echo "If it fails from every agent's machine too, publish the feed somewhere"
  echo "outside GitHub entirely (Cloudflare Pages / Netlify / Vercel are free"
  echo "and independent) and point the policy there."
  exit 1
fi

echo "Point the Workspace policy at the first working mirror above:"
echo
echo "  $ID;$BEST"
echo
echo "admin.google.com -> Devices -> Chrome -> Apps & extensions -> Users and"
echo "browsers -> the existing entry for this extension -> edit its Update URL."
echo "Same policy row, one field. No re-enrolment, nothing else changes."
