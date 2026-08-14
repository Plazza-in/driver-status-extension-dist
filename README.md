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

### If a host gets blocked again — the runbook

This already happened once and will not be the last time, so the recovery
is deliberately short.

**Symptom:** the side panel shows its "auto-updates appear stuck" banner, or
someone reports being on an old version, or a release you pushed never
reaches anyone.

```bash
cd ~/Desktop/driver-status-extension-dist
./check-mirrors.sh
```

It reports which feeds are reachable **from that machine** and prints the
exact policy string to paste. Run it on an affected agent's machine when you
can — a mirror that works from your laptop may still be blocked on theirs,
and theirs is the network that matters.

Then edit **one field**: `admin.google.com → Devices → Chrome → Apps &
extensions → Users and browsers` → the existing entry → its Update URL.
Same policy row. No re-enrolment, no new setup, nothing else changes — and
it's the same console you set the policy up in, so you aren't waiting on
anyone else to do it.

**If every mirror is down everywhere**, all three are GitHub-backed, so
publish the feed somewhere independent (Cloudflare Pages, Netlify and Vercel
are free and unrelated to GitHub) and point the policy there. The `.crx` and
`update.xml` are just two static files; any host that serves them over plain
HTTPS will do.

### Making this never need a policy edit again

The permanent fix is a **custom domain** — e.g. `ext.plazza.in` as a CNAME to
GitHub Pages, with the policy pointing at
`https://ext.plazza.in/update.xml` forever. Moving hosts then becomes a DNS
change instead of a Workspace change, and a `plazza.in` hostname is far less
likely to be caught by the kind of security policy that blocks public code
CDNs in the first place.

Two honest caveats: it needs whoever controls `plazza.in` DNS to add one
record (a one-time ask), and it defends against *hostname*-based blocks —
the common kind, and what appears to have hit
`raw.githubusercontent.com` — but not a block on the underlying IPs, since
the CNAME resolves to the same servers.

**Worth doing while updates still work.** The mirror list the extension
checks itself against is compiled into the shipped `.crx`, so it can only be
changed by shipping an update — which requires updates to be working. Adding
a stable domain after everything is already stuck is exactly too late.

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
