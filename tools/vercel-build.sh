#!/usr/bin/env bash
# Vercel build for the ITSR Flutter Web app (used by vercel.json).
#
# Vercel's build image has no Flutter SDK, so this installs a pinned Flutter
# release and builds build/web. Configuration comes from Vercel project
# environment variables (never from the repo):
#   SUPABASE_URL        https://<ref>.supabase.co
#   SUPABASE_ANON_KEY   the PUBLISHABLE key (sb_publishable_...); a secret key
#                       is refused here and by the app itself
#   ITSR_ENVIRONMENT    optional label, e.g. "staging" (default "production")
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter-$FLUTTER_VERSION}"

: "${SUPABASE_URL:?SUPABASE_URL is not set in the Vercel project environment}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is not set in the Vercel project environment}"
case "$SUPABASE_ANON_KEY" in
  sb_secret_*|*service_role*) echo "Refusing to build: SUPABASE_ANON_KEY is a secret key" >&2; exit 1 ;;
esac

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Installing Flutter $FLUTTER_VERSION ..."
  mkdir -p "$FLUTTER_DIR"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$FLUTTER_DIR" --strip-components=1
fi
export PATH="$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory '*' >/dev/null 2>&1 || true
export FLUTTER_SUPPRESS_ANALYTICS=true CI=true

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=ENVIRONMENT="${ITSR_ENVIRONMENT:-production}"
echo "Built $(find build/web -type f | wc -l) files into build/web"
