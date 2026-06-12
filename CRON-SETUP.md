# Cron setup — keeping the auto-enroll sweep alive

`auto-enroll.yml` has a native `schedule:` (daily 03:00 UTC), but GitHub **disables a scheduled
workflow after 60 days of repository inactivity**. To guarantee the sweep keeps running, also trigger
it from **cron-job.org** via `workflow_dispatch` — the same external-scheduler pattern this project
already uses for the dashboard refresh. `workflow_dispatch` is exempt from the 60-day rule.

The native `schedule:` is kept as a free fallback. The sweep is idempotent and uses a `concurrency`
group, so an occasional double-fire (native + cron-job.org on the same day) is harmless — the second
run queues behind the first and is a no-op when everything is already enrolled.

## 1. Create a minimal dispatch PAT

cron-job.org needs a token that can trigger the workflow. Use a **dedicated, least-privilege**
fine-grained PAT — separate from `ENROLL_TOKEN` (which the workflow uses internally for its writes):

- GitHub → **Settings → Developer settings → Fine-grained tokens → Generate new token**
- **Resource owner:** `aniket-ghosh-zoomrx`
- **Repository access:** *Only select repositories* → **`security-workflows`**
- **Permissions → Actions: Read and write** (Metadata: Read is auto-added)
- **Expiration:** short; rotate on a calendar

This token can do exactly one thing — trigger workflows in `security-workflows`. Nothing else.
(You could instead extend your existing dashboard cron-job.org PAT to also cover this repo, but a
separate minimal token keeps the blast radius small.)

## 2. Create the cron-job.org job

| Field | Value |
|---|---|
| **URL** | `https://api.github.com/repos/aniket-ghosh-zoomrx/security-workflows/actions/workflows/auto-enroll.yml/dispatches` |
| **Method** | `POST` |
| **Request body** | `{"ref":"main"}` |
| **Schedule** | once daily (e.g. **08:45 IST** — offset from the 08:15 dashboard job so they don't pile up) |

**Headers:**

```
Accept: application/vnd.github+json
Authorization: Bearer <YOUR_DISPATCH_PAT>
X-GitHub-Api-Version: 2022-11-28
Content-Type: application/json
```

**Expected response:** HTTP **204 No Content** = success. cron-job.org treats any 2xx as success by
default. (If you set a custom success rule expecting `200`, change it to accept 204.)

## 3. Verify

1. cron-job.org → the job → **Run now / Test run**. Expect **204**.
2. GitHub → `security-workflows` → **Actions → "Auto-enroll secret scanning"** → a new run appears,
   triggered *"via workflow_dispatch"*. Open it and read the step summary: **Enrolled / Skipped / Failed**.
3. The dispatch PAT only *starts* the run; the sweep authenticates its own writes with the
   `ENROLL_TOKEN` Actions secret.

## Notes

- **Treat the dispatch PAT as a credential** — it can trigger CI in `security-workflows`. It lives only
  in cron-job.org's header config; never commit it.
- The sweep **fails loud** if it can't list your repos (it won't report a green no-op on a broken
  token), so a cron-job.org "success" (204 dispatch) plus a **green Actions run** together confirm
  end-to-end health. Watch the Actions run conclusion, not just the cron-job.org dispatch result.
