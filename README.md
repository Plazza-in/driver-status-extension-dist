# Plazza Driver Status — self-hosted update feed

This repo exists for one reason: Chrome's extension auto-updater makes a
plain, **unauthenticated** HTTPS request when it checks for updates — no
browser, no cookies, no Google login. `support-extension.apps.plazza.in`
(and every other `*.apps.plazza.in` service) sits behind Cognito SSO on
every path, so the updater can never read anything hosted there. This repo
is public specifically so `update.xml` and the `.crx` are reachable by a
bare `curl`, which is all Chrome's updater can do.

Nothing sensitive lives here. The `.crx` is the same code that would have
shipped via the Chrome Web Store or a "Load unpacked" folder either way —
making it public doesn't expose anything that wasn't already going out to
every laptop that installs the extension by any method.

**The signing private key is NOT in this repo** — it lives at
`~/Downloads/plazza-extension-signing-key.pem` on [whoever manages
releases]'s machine, outside any git repo, precisely so it never ships.
Losing it means a new extension ID and a reinstall for everyone force-
installed via this feed.

## How agents actually get this

Nobody visits this repo or clicks a link here. A Chrome/Workspace admin
sets one Chrome policy (`ExtensionInstallForcelist`) pointing at
`update.xml` below, on browsers enrolled in Chrome Browser Cloud
Management. From then on, Chrome:

1. periodically fetches `update.xml` (a few times a day, or immediately if
   an admin pushes a policy refresh / the agent restarts Chrome)
2. compares the `version` there against what's installed
3. if newer, downloads the `codebase` URL (the `.crx`) and installs it —
   silently, no click, no restart required beyond what Chrome does anyway

**Policy value** (give this to whoever has Chrome management admin rights):

```
ijocfdgbkehhnbhpoppeeoelegfildde;https://raw.githubusercontent.com/Plazza-in/driver-status-extension-dist/main/update.xml
```

Set under **admin.google.com → Devices → Chrome → Apps & extensions →
Users & browsers**, on the support team's org unit, as a **Force install**
entry using **"Custom App"** / by extension ID + update URL (not "search
the Chrome Web Store" — this extension isn't listed there).

## Releasing a new version

From the main extension repo (`plazza-driver-status-extension`), after
bumping `version` in `manifest.json`:

```bash
# 1. Stage only the runtime files (not server/, docs, install scripts, zips)
STAGE=/tmp/ext-staging
rm -rf "$STAGE" && mkdir -p "$STAGE/icons"
cp manifest.json background.js content-freshchat.js \
   sidepanel.html sidepanel.js sidepanel.css "$STAGE/"
cp icons/*.png "$STAGE/icons/"

# 2. Chrome requires PKCS#8 — convert the key into a throwaway temp copy,
#    pack, then shred the copy. Never commit or leave this lying around.
openssl pkcs8 -topk8 -nocrypt \
  -in ~/Downloads/plazza-extension-signing-key.pem \
  -out /tmp/signing-key-pkcs8.pem

"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --pack-extension="$STAGE" \
  --pack-extension-key=/tmp/signing-key-pkcs8.pem \
  --user-data-dir=/tmp/chrome-pack-profile \
  --headless --no-first-run

shred -u /tmp/signing-key-pkcs8.pem || rm -f /tmp/signing-key-pkcs8.pem
rm -rf /tmp/chrome-pack-profile

# 3. Move the crx here, versioned, and update update.xml's version + codebase
mv "$STAGE.crx" ~/Desktop/driver-status-extension-dist/plazza-driver-status-vX.Y.Z.crx
```

Then edit `update.xml`'s `version` and `codebase` filename to match, and:

```bash
git add -A
git commit -m "Release vX.Y.Z"
git push
```

Enrolled browsers pick it up on their next update check — nobody needs to
do anything, including you, beyond this push. Old `.crx` versions can stay
in the repo (harmless, just history) or be deleted once you're confident
everyone's updated past them.
