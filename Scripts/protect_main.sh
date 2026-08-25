#!/bin/bash
# Applies server-side protection to main: no direct pushes, no force-pushes, no deletion, and CI
# must pass. Applies to everyone including admins — `bypass_actors` is deliberately empty.
#
# GitHub does not offer this on free *private* repositories, so this will fail with a 403 until
# the repo is public (or the account is on Pro). Run it the moment you flip visibility.
set -euo pipefail

REPO="${1:-timfedo/DesktopCasino}"

read -r -d '' RULESET <<'JSON' || true
{
  "name": "main protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge", "squash", "rebase"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [{ "context": "build-and-test" }]
      }
    }
  ]
}
JSON

echo "Applying branch protection to $REPO..."
if printf '%s' "$RULESET" | gh api -X POST "repos/$REPO/rulesets" --input - \
     --jq '"Created ruleset #\(.id): \(.name) [\(.enforcement)]"'; then
  echo
  echo "main now requires a pull request with build-and-test passing."
  echo "Zero approvals are required, so you can review and merge your own PRs."
else
  echo >&2
  echo "Failed. If that was a 403, the repo is still private on a free plan:" >&2
  echo "  gh repo edit $REPO --visibility public --accept-visibility-change-consequences" >&2
  exit 1
fi
