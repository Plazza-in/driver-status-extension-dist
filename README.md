# Plazza Driver Status — self-hosted update feed

This repo exists for one reason: Chrome's extension auto-updater makes a
plain, **unauthenticated** HTTPS request when it checks for updates — no
browser, no cookies, no Google login. `support-extension.apps.plazza.in`
(and every other `*.apps.plazza.in` service) sits behind Cognito SSO on
every path, so the updater can never read anything hosted there. This repo
is public specifically so `update.xml` and the `.crx` are reachable by a
bare `curl`, which is all Chrome's updater can do.

**Served via GitHub Pages (`plazza-in.github.io`), not
`raw.githubusercontent.com`** — the latter hung indefinitely (no error, just
never completed) from two independent networks when first tested
2026-08-14, a classic signature of a network silently blocking that
specific hostname. `github.io` is a different domain entirely, unaffected.
If Pages ever has the same problem, the fix is the same idea again: move to
yet another domain and update the Workspace policy's Update URL to match —
see "Releasing a new version" below for where that URL is defined.

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
ijocfdgbkehhnbhpoppeeoelegfildde;https://plazza-in.github.io/driver-status-extension-dist/update.xml
```

Set under **admin.google.com → Devices → Chrome → Apps & extensions →
Users & browsers**, on the support team's org unit, as a **Force install**
entry using **"Custom App"** / by extension ID + update URL (not "search
the Chrome Web Store" — this extension isn't listed there).

## What happens when this breaks

The failure mode worth designing against is not a loud one. If the update
URL is unreachable from an agent's network, Chrome shows no error, the
agent has no reason to open `chrome://extensions`, and they simply keep
running an old version forever. Three layers exist so that can't stay
invisible:

1. **The extension checks its own version** (`background.js`, every 6h and
   on browser start) against **three independent domains** — GitHub Pages,
   jsDelivr, and GitHub's raw CDN. One being blocked or down doesn't blind
   it. If it finds itself behind, it first calls
   `chrome.runtime.requestUpdateCheck()` to make Chrome retry immediately —
   a genuine self-heal, not just a complaint.
2. **The side panel says so**, top of the panel, if an update has been
   available for over 24h and still hasn't installed. Under that threshold
   it stays quiet, because Chrome routinely takes a few hours and crying
   wolf at every release would train people to ignore it. If every mirror
   is unreachable it notes that quietly in the footer instead — "can't
   tell" is different from "you're behind".
3. **`release.sh` refuses to ship a broken release** — see below.

None of this can force an update through a network that blocks all three
domains. What it does guarantee is that somebody *finds out*, instead of a
silently frozen extension being discovered weeks later.

**If GitHub Pages itself ever gets blocked:** `update-jsdelivr.xml` is
already published, pointing at the same `.crx` on jsDelivr's CDN. Switch
the Workspace policy's update URL to
`https://cdn.jsdelivr.net/gh/Plazza-in/driver-status-extension-dist@main/update-jsdelivr.xml`
— one field, same policy row, no re-enrolment and nothing else to change.

## Releasing a new version

Bump `version` in the extension's `manifest.json`, then:

```bash
cd ~/Desktop/driver-status-extension-dist
./release.sh                 # or: ./release.sh /path/to/extension-source
git add -A && git commit -m "Release vX.Y.Z" && git push
```

That's it. The script stages the runtime files, packs and signs the `.crx`,
and regenerates every feed variant from one source of truth.

It also refuses to produce a release that would break force-install
silently, which is the whole reason it exists rather than a list of manual
steps:

- **Wrong signing key** → the extension ID changes, and enrolled browsers
  would stop recognising the extension entirely. The script derives the ID
  from the key and aborts unless it matches the pinned one.
- **Version not bumped** → Chrome ignores any feed whose version isn't
  strictly newer, so the release would appear to succeed and do nothing.
  The script aborts if that `.crx` already exists.
- **Feeds drifting out of sync** → both feed variants are regenerated
  together, so one can't be left pointing at an older build.
- **Syntax errors** → `node --check` on every script and a JSON parse of
  the manifest, before anything is packed.

The temp PKCS#8 copy of the private key is shredded on exit, including if
the script fails partway through.

Old `.crx` versions can stay in the repo (harmless history) or be deleted
once everyone's updated past them.
