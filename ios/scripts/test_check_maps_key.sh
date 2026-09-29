#!/bin/sh
# Tests for check_maps_key.sh and for the CI workflow that relies on it.
#
# Run from anywhere:  sh ios/scripts/test_check_maps_key.sh
# Uses only dummy, non-secret values - never a real Maps key.

set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/check_maps_key.sh"
workflow="$here/../../.github/workflows/build-flutter-mobile.yml"

DUMMY="DUMMY-NOT-A-REAL-MAPS-KEY-4242"
PLACEHOLDER="YOUR_GOOGLE_MAPS_IOS_API_KEY"
UNSET="__UNSET__"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# check <expected-exit> <description> <key|__UNSET__> [opt-out value]
# Runs the script in a clean environment and asserts the exit code and that
# the output never contains the supplied key.
check() {
  expected=$1
  desc=$2
  key=$3
  optout=${4:-}

  set -- PATH="$PATH"
  if [ "$key" != "$UNSET" ]; then
    set -- "$@" GOOGLE_MAPS_API_KEY="$key"
  fi
  if [ -n "$optout" ]; then
    set -- "$@" GOHARD_ALLOW_MISSING_MAPS_KEY="$optout"
  fi

  out=$(env -i "$@" /bin/sh "$script" 2>&1)
  status=$?

  if [ "$status" -ne "$expected" ]; then
    fail "$desc (exit $status, expected $expected)"
    return
  fi
  trimmed=$(printf '%s' "$key" | tr -d '[:space:]')
  if [ "$key" != "$UNSET" ] && [ -n "$trimmed" ]; then
    case "$out" in
      *"$trimmed"*)
        fail "$desc (output contains the supplied key)"
        return
        ;;
    esac
  fi
  echo "ok: $desc"
}

# --- check_maps_key.sh ------------------------------------------------------

check 1 "A: missing key fails" "$UNSET"
check 1 "B: empty key fails" ""
check 1 "B2: whitespace-only key fails" "   "
check 1 "C: documented placeholder fails" "$PLACEHOLDER"
check 1 "C2: unresolved build-setting reference fails" '$(GOOGLE_MAPS_API_KEY)'
check 0 "D: dummy configured key succeeds" "$DUMMY"
check 0 "E: missing key + opt-out succeeds (compile-only)" "$UNSET" "YES"
check 0 "F: placeholder + opt-out succeeds (opt-out overrides)" "$PLACEHOLDER" "YES"
check 1 "G: opt-out must be exactly YES (lowercase ignored)" "$UNSET" "yes"
check 0 "H: configured key + opt-out succeeds" "$DUMMY" "YES"

# --- CI workflow contract -----------------------------------------------------
# Structural checks on the two iOS jobs, scoped to each job's own block.

# Print the lines of one top-level job (tolerates CRLF checkouts).
job_block() {
  awk -v job="$1" '
    { sub(/\r$/, "") }
    $0 ~ "^  " job ":" { on = 1; print; next }
    on && /^  [A-Za-z0-9_-]+:/ { exit }
    on { print }
  ' "$workflow"
}

unsigned=$(job_block build-ios)
signed=$(job_block build-ios-signed)

if [ -z "$unsigned" ] || [ -z "$signed" ]; then
  fail "workflow: could not find the build-ios / build-ios-signed jobs"
else
  # Every artifact upload in the unsigned job must be gated on a configured
  # Maps key, so a keyless compile-only build is never handed out.
  ungated=$(printf '%s\n' "$unsigned" | awk '
    /^    - / { gated = 0 }
    /^      if: .*steps\.maps\.outputs\.configured == .true./ { gated = 1 }
    /uses: actions\/upload-artifact/ && !gated { print }
  ')
  uploads=$(printf '%s\n' "$unsigned" | grep -c "uses: actions/upload-artifact")
  if [ "$uploads" -eq 0 ]; then
    fail "workflow: unsigned job has no artifact upload to check"
  elif [ -n "$ungated" ]; then
    fail "workflow: unsigned job uploads an IPA without the configured-key gate"
  else
    echo "ok: workflow: unsigned IPA upload requires a configured Maps key"
  fi

  if printf '%s\n' "$unsigned" | grep -q "GOHARD_ALLOW_MISSING_MAPS_KEY = YES"; then
    echo "ok: workflow: keyless unsigned build opts into compile-only explicitly"
  else
    fail "workflow: keyless unsigned build does not opt into compile-only"
  fi

  if printf '%s\n' "$signed" | grep -q "ios/scripts/check_maps_key.sh"; then
    echo "ok: workflow: signed job validates the key with check_maps_key.sh"
  else
    fail "workflow: signed job does not run check_maps_key.sh"
  fi

  if printf '%s\n' "$signed" | grep -Eq "GOHARD_ALLOW_MISSING_MAPS_KEY *= *YES"; then
    fail "workflow: signed job enables the compile-only opt-out"
  else
    echo "ok: workflow: signed job never enables the compile-only opt-out"
  fi
fi

echo
if [ "$failures" -ne 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
