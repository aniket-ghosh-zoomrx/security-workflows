# security-workflows

Central, reusable CI security workflows for `aniket-ghosh-zoomrx` projects.

Currently ships **TruffleHog secret scanning** as a reusable GitHub Actions workflow. The goal is one
place to define the scan, and a tiny per-repo caller so every project gets the same protection and
updates land centrally.

## What it does

[TruffleHog](https://github.com/trufflesecurity/trufflehog) scans commits for leaked credentials using
800+ detectors. Its defining feature is **live verification** — it calls the credential's own API to
confirm the secret is actually active. We run it **verified-only** (`--results=verified --fail`), so the
build fails only on a confirmed-live secret. That keeps false-positive friction near zero.

The scan runs on a **GitHub-hosted Ubuntu runner**, so it needs nothing installed on any developer
machine.

## Adopt it in a repo (2 minutes)

1. Copy [`caller-template.yml`](./caller-template.yml) into the target repo as
   `.github/workflows/trufflehog.yml`.
2. Set the `branches:` list to the repo's default branch (e.g. `master`).
3. Commit & push. Pushing a workflow file needs a token with the **`workflow`** scope.

That's it — every push to the default branch and every pull request now gets scanned.

## One-time central setup (already done)

Because this repo is **private**, other private repos owned by the same account must be granted access to
call its reusable workflow:

- **Settings → Actions → General → Access →** *"Accessible from repositories owned by the user account."*
- Equivalent API: `PUT /repos/aniket-ghosh-zoomrx/security-workflows/actions/permissions/access`
  with `{"access_level":"user"}`.

## Scan scope reference

| Flag | Meaning |
|---|---|
| `--results=verified` | Only report credentials confirmed **live** by an API call (our default). |
| `--results=verified,unknown` | Also report plausible-but-unverifiable matches (broader, noisier). |
| `--fail` | Exit non-zero (code 183) on a finding → fails the CI job. **The action adds this automatically — do NOT put it in `extra_args`** (passing it twice errors: `flag 'fail' cannot be repeated`). |

Override per-repo via the caller's `with: extra_args:` (see the template's commented example).
Only override the `--results=...` scope; never re-add `--fail`.

## Versioning (why callers pin `@v1`)

Callers reference the reusable workflow at a **tag** (`...trufflehog-reusable.yml@v1`), not `@main`.
This is deliberate supply-chain hygiene for a security workflow: a caller pinned to `@main` runs whatever
is on `main` at trigger time, so an unintended (or malicious) edit to `main` would silently change the CI
of **every** repo that calls it. Pinning to `@v1` means callers only move when the tag is deliberately
re-pointed.

**To ship a change to the reusable workflow:**

```bash
# after committing the change to main:
git tag -f v1            # move the v1 tag to the new commit
git push -f origin v1    # callers on @v1 pick it up on their next run
```

(For stricter pinning you can reference a full commit SHA instead of `v1`. Bumping a major version —
e.g. `v2` for a breaking change — lets callers migrate on their own schedule.)

## ⚠️ Why there is no local pre-commit hook

A local TruffleHog CLI pre-commit hook was intended as a second layer (catch secrets *before* they're
committed). It is **not deployable on the current developer machine** because the endpoint is locked down
by **Windows Defender Application Control (WDAC) in *enforced* mode** (CodeIntegrity enforcement status 2,
plus AppLocker). Under WDAC enforcement:

- `scoop` can't install (PowerShell runs in `ConstrainedLanguage` mode), and
- any unsigned / non-allowlisted `trufflehog.exe` is blocked from executing machine-wide, regardless of
  how it's installed (winget, direct download, install script).
- No Docker/Podman is available to run it in a container.

**To enable the local hook later**, IT/security must add a WDAC allowlist rule for `trufflehog.exe`
(publisher or hash rule), or provide a managed/signed install. Once the CLI can run, a global hook can be
installed via `git config --global core.hooksPath` with **chaining dispatchers** that scan and then
delegate to each repo's own `.git/hooks/*` (so existing hooks like auto-push are preserved). Until then,
**CI is the enforced layer.**

## Layers of the secret-scanning apparatus

| Layer | Status | Where it runs |
|---|---|---|
| CI reusable workflow + per-repo caller | ✅ Active | GitHub-hosted runner |
| Global `~/.claude/CLAUDE.md` directive (Claude never commits secrets) | ✅ Active | Claude Code sessions |
| Local pre-commit CLI hook | ⛔ Blocked by WDAC — needs IT allowlist | Developer machine |
| GitHub Push Protection (server-side push blocking) | ⏸ Deferred (private repos need GHAS) | GitHub server |
