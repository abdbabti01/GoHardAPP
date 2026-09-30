#!/bin/sh
# Build-time contract for the Google Maps iOS API key.
#
# Why: the Google Maps iOS SDK aborts the whole app
# (+[GMSServices checkServicePreconditions]) the first time a map is created
# if GMSServices.provideAPIKey was never called. AppDelegate only calls it
# when GOOGLE_MAPS_API_KEY reaches Info.plist through the gitignored
# ios/Flutter/Secrets.xcconfig. Without this check, a keyless build compiles,
# signs, installs and launches normally, then crashes when Running opens a
# map. This check fails that build instead.
#
# Runs as the Runner target's "Check Google Maps key" build phase (Xcode
# exports build settings, including those from Secrets.xcconfig, as
# environment variables) and from CI. It never prints the key.
#
# Inputs (environment / build settings):
#   GOOGLE_MAPS_API_KEY            the iOS Maps key; required.
#   GOHARD_ALLOW_MISSING_MAPS_KEY  set to exactly YES for a compile-only
#                                  build. Overrides a missing or placeholder
#                                  key. Such a build crashes when a map opens
#                                  and must never be installed for testing or
#                                  distributed.

PLACEHOLDER="YOUR_GOOGLE_MAPS_IOS_API_KEY"

if [ "${GOHARD_ALLOW_MISSING_MAPS_KEY:-}" = "YES" ]; then
  echo "warning: GOHARD_ALLOW_MISSING_MAPS_KEY=YES - Google Maps key check skipped. This is a COMPILE-ONLY build: opening Running (any map) will crash the app. Do not install it for device testing or distribute it."
  exit 0
fi

# Whitespace-trimmed copy, used only for comparisons - never printed.
key=$(printf '%s' "${GOOGLE_MAPS_API_KEY:-}" | tr -d '[:space:]')

problem=""
if [ -z "$key" ]; then
  problem="GOOGLE_MAPS_API_KEY is not set or is empty"
elif [ "$key" = "$PLACEHOLDER" ]; then
  problem="GOOGLE_MAPS_API_KEY is still the placeholder from Secrets.xcconfig.example"
else
  case "$key" in
    *'$('* | *'${'*)
      problem="GOOGLE_MAPS_API_KEY is an unresolved build-setting reference"
      ;;
  esac
fi

if [ -n "$problem" ]; then
  cat >&2 <<EOF
error: $problem.
error: A build without a Google Maps iOS key installs and launches, then crashes (GMSServices abort) as soon as Running opens a map.
error: To fix: copy ios/Flutter/Secrets.xcconfig.example to ios/Flutter/Secrets.xcconfig (never commit it) and set GOOGLE_MAPS_API_KEY to a real iOS key restricted to the ca.gohardapp bundle ID.
error: For a compile-only build that will never be installed, put GOHARD_ALLOW_MISSING_MAPS_KEY = YES in that file instead.
EOF
  exit 1
fi

echo "Google Maps iOS key is configured."
exit 0
