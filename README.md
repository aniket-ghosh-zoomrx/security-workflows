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

## Auto-enrollment for new repos

Two mechanisms keep new repos covered without manual copying.

### 1. `ghnew` — instant enrollment at creation time

[`tools/ghnew.sh`](./tools/ghnew.sh) is a Git Bash function that creates a repo **and** adds the `@v1`
caller in one step:

```bash
source "$HOME/security-workflows/tools/ghnew.sh"   # add this line to ~/.bashrc
ghnew my-new-repo            # private repo + secret scanning (default)
ghnew my-new-repo --public   # public
ghnew my-new-repo --clone    # also clone locally (auto-pulls the caller)
```

Defaults to **private**; requires `gh` with the `workflow` token scope. Covers only repos you create
through `ghnew` (not the web UI) — the sweep below is the catch-all.

### 2. `auto-enroll.yml` — daily self-healing sweep

[`.github/workflows/auto-enroll.yml`](./.github/workflows/auto-enroll.yml) runs daily (and on
`workflow_dispatch`). It lists every owned, non-archived, non-fork repo and adds the `@v1` caller to any
that lack it — catching repos created via the web UI, import, or anything `ghnew` misses. It is
**idempotent** (skips already-enrolled repos), **non-clobbering** (a create-only PUT never overwrites an
existing `trufflehog.yml`), and **fails loud** (aborts rather than reporting a green no-op if the repo
listing errors).

**Activation — create the `ENROLL_TOKEN` secret (one-time):**

1. GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**.
2. **Resource owner:** `aniket-ghosh-zoomrx`. **Repository access:** *All repositories*.
3. **Permissions → Repository permissions:** **Contents:** Read and write · **Workflows:** Read and write · **Metadata:** Read-only (auto-selected).
4. **Expiration:** keep it short (e.g. 90 days) — this is a high-privilege token; rotate on a calendar.
5. Generate and copy the token.
6. This repo → **Settings → Secrets and variables → Actions → New repository secret** → name **`ENROLL_TOKEN`**, value = the token.
7. Test: **Actions → "Auto-enroll secret scanning" → Run workflow**, then read the run summary.

**Operational caveats:**

- **`ENROLL_TOKEN` is a top-tier credential** — Contents + Workflows write across *all* your repos. Guard
  who can read this repo's secrets; prefer a short expiry + rotation, or a GitHub App installation token
  minted per-run instead of a static PAT.
- **The 60-day rule:** GitHub disables a scheduled workflow after 60 days with no repo activity. To
  guarantee the sweep keeps firing, also POST a `workflow_dispatch` from an external scheduler — this
  project already uses **cron-job.org** for the dashboard, so add a second job hitting
  `POST /repos/aniket-ghosh-zoomrx/security-workflows/actions/workflows/auto-enroll.yml/dispatches` with
  body `{"ref":"main"}` (`workflow_dispatch` is exempt from the 60-day rule). Full config in
  [CRON-SETUP.md](./CRON-SETUP.md).
- **Default-branch renames:** the generated caller pins `on: push: branches: [<default>]`. If a repo's
  default branch is renamed later, re-run enrollment; the `pull_request:` trigger is unaffected either way.

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

**Protect the `v1` tag** so it can't be force-moved by accident or a leaked token: this repo →
**Settings → Rules → Rulesets → New tag ruleset** → target `v1` → restrict updates and deletions.

## Upgrading the scanner

The reusable workflow pins the TruffleHog action to a **full commit SHA** (not `@main`) and the scanner
image to a fixed **`version`** tag — so an upstream branch push can't silently change what runs in every
enrolled repo. To upgrade deliberately:

1. Pick the new release: `gh release view --repo trufflesecurity/trufflehog`.
2. Resolve its commit SHA: `gh api repos/trufflesecurity/trufflehog/commits/<tag> -q .sha`.
3. In `trufflehog-reusable.yml` update both lines: `uses: trufflesecurity/trufflehog@<sha>  # <tag>` and `version: "<tag>"`.
4. Commit, then move the `v1` tag (see Versioning) so callers pick it up on their next run.

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
| Auto-enrollment: `ghnew` (instant) + daily sweep (catch-all) | ✅ Active (sweep needs `ENROLL_TOKEN`) | Dev machine + GitHub-hosted runner |
| Global `~/.claude/CLAUDE.md` directive (Claude never commits secrets) | ✅ Active | Claude Code sessions |
| Local pre-commit CLI hook | ⛔ Blocked by WDAC — needs IT allowlist | Developer machine |
| GitHub Push Protection (native, pre-push block) | ✅ Active on this (public) repo; 🔒 private code repos need GHAS | GitHub server |
