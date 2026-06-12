#!/usr/bin/env bash
# ghnew — create a new GitHub repo under aniket-ghosh-zoomrx and immediately
# enroll it in TruffleHog secret scanning (caller pinned @v1).
#
# Install (Git Bash): add this line to ~/.bashrc, then restart Git Bash:
#   source "$HOME/security-workflows/tools/ghnew.sh"   # adjust path to your clone
# ...or copy the function body straight into ~/.bashrc.
#
# Requires: gh CLI, authenticated, with the 'workflow' token scope (creating a
# file under .github/workflows/ needs it). Verify: gh auth status
#
# Usage:
#   ghnew my-new-repo                 # PRIVATE repo + secret scanning (default)
#   ghnew my-new-repo --public        # public
#   ghnew my-new-repo --clone         # also clone locally (auto-pulls the caller after)
ghnew() {
  local owner="aniket-ghosh-zoomrx"
  local name="${1:-}"
  shift 2>/dev/null || true
  if [ -z "$name" ]; then
    echo "usage: ghnew <repo-name> [--public|--private|--internal] [extra gh repo create flags]" >&2
    return 1
  fi

  # Default to private unless a visibility flag is present. Iterate REAL argv
  # tokens (not a flattened string) so a visibility keyword inside a quoted
  # value — e.g. --description "a --public tool" — can't suppress the default.
  local visflag="--private" a
  for a in "$@"; do
    case "$a" in
      --public|--private|--internal) visflag=""; break ;;
    esac
  done

  echo "Creating $owner/$name ..."
  # shellcheck disable=SC2086  # $visflag is intentionally split (empty or one flag)
  gh repo create "$owner/$name" $visflag "$@" || return 1

  # Resolve the default branch name (works even for an empty repo).
  local branch
  branch=$(gh api "repos/$owner/$name" -q .default_branch 2>/dev/null)
  [ -z "$branch" ] && branch="main"

  # Branch quoted as a YAML string (injection-safe for exotic branch names).
  local caller
  caller=$(printf '%s\n' \
    "name: Secret Scan" \
    "" \
    "on:" \
    "  push:" \
    "    branches:" \
    "      - \"$branch\"" \
    "  pull_request:" \
    "" \
    "permissions:" \
    "  contents: read" \
    "" \
    "jobs:" \
    "  trufflehog:" \
    "    uses: $owner/security-workflows/.github/workflows/trufflehog-reusable.yml@v1")

  if gh api --method PUT "repos/$owner/$name/contents/.github/workflows/trufflehog.yml" \
       -f message="Add TruffleHog secret-scan caller (pinned @v1)" \
       -f content="$(printf '%s\n' "$caller" | base64 | tr -d '\n')" \
       -f branch="$branch" >/dev/null; then
    echo "✅ $owner/$name created and enrolled in secret scanning (@v1, branch '$branch')."
  else
    echo "⚠ $owner/$name was created, but adding the secret-scan caller failed." >&2
    echo "  The daily auto-enroll sweep will pick it up, or add it manually." >&2
    return 1
  fi

  # If the repo was cloned, fetch the just-added workflow file so the local
  # working copy isn't behind the remote default branch.
  case " $* " in
    *" --clone "*)
      if [ -d "$name/.git" ]; then
        echo "Pulling enrollment commit into local clone ..."
        git -C "$name" pull --ff-only || echo "  (pull failed — run: git -C \"$name\" pull)"
      fi
      ;;
  esac
}
