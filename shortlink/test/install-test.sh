#!/bin/bash

set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT

PLUGIN_ID="io.github.regionallyfamous.one-bit-bureau"
TAG="v1.2.3"
VERSION="1.2.3"
MOCK_BIN="$WORK/bin"
MOCK_LOG="$WORK/calls.log"
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/omarchy" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'omarchy:%s\n' "$*" >>"$MOCK_LOG"
case "$*" in
  "plugin validate "*) exit 0 ;;
  "plugin list --json") printf '[{"id":"io.github.regionallyfamous.one-bit-bureau","enabled":false}]\n' ;;
  "plugin disable "* | "plugin remove "*) exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$MOCK_BIN/omarchy"

cat >"$MOCK_BIN/omarchy-shell" <<'MOCK'
#!/bin/bash
set -euo pipefail
printf 'omarchy-shell:%s\n' "$*" >>"$MOCK_LOG"
MOCK
chmod +x "$MOCK_BIN/omarchy-shell"

make_package() {
  local package_dir="$1" setup_status="$2"
  local source_repo="$package_dir/source"
  local bundle_name="one-bit-bureau-$TAG.bundle"
  mkdir -p "$source_repo" "$package_dir/payload"
  git -C "$source_repo" init -q
  git -C "$source_repo" config user.name "One-Bit Bureau Tests"
  git -C "$source_repo" config user.email "tests@example.invalid"
  cat >"$source_repo/manifest.json" <<JSON
{"schemaVersion":1,"id":"$PLUGIN_ID","name":"One-Bit Bureau","version":"$VERSION","author":"RegionallyFamous","license":"MIT","description":"Verified installer fixture","kinds":["service"],"entryPoints":{"service":"Service.qml"}}
JSON
  printf 'import QtQuick\nItem {}\n' >"$source_repo/Service.qml"
  cat >"$source_repo/setup" <<SETUP
#!/bin/bash
set -euo pipefail
printf 'setup:%s\n' "\$*" >>"\$MOCK_LOG"
exit $setup_status
SETUP
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm "fixture"
  git -C "$source_repo" tag -a "$TAG" -m "$TAG"
  commit=$(git -C "$source_repo" rev-list -n 1 "$TAG")
  git -C "$source_repo" bundle create "$package_dir/payload/$bundle_name" "refs/tags/$TAG"
  bundle_sha=$(sha256sum "$package_dir/payload/$bundle_name" | awk '{print $1}')
  cp "$ROOT/release/install" "$package_dir/payload/install"
  cp "$ROOT/scripts/one_bit_bureau_secure_io.py" "$package_dir/payload/one_bit_bureau_secure_io.py"
  jq -n \
    --arg tag "$TAG" \
    --arg version "$VERSION" \
    --arg commit "$commit" \
    --arg bundleName "$bundle_name" \
    --arg bundleSha "$bundle_sha" \
    '{schemaVersion:1,product:"One-Bit Bureau",repository:"RegionallyFamous/one-bit-bureau",tag:$tag,version:$version,commit:$commit,bundle:{name:$bundleName,sha256:$bundleSha}}' \
    >"$package_dir/payload/RELEASE.json"
}

echo "== verified release installer stages and adopts the exact bundled commit"
SUCCESS="$WORK/success"
make_package "$SUCCESS" 0
SUCCESS_HOME="$WORK/success-home"
mkdir -p "$SUCCESS_HOME"
: >"$MOCK_LOG"
export MOCK_LOG
HOME="$SUCCESS_HOME" PATH="$MOCK_BIN:$PATH" bash "$SUCCESS/payload/install" >"$WORK/success.log"
SUCCESS_TARGET="$SUCCESS_HOME/.config/omarchy/plugins/$PLUGIN_ID"
[[ -d $SUCCESS_TARGET/.git ]]
expected_commit=$(jq -r '.commit' "$SUCCESS/payload/RELEASE.json")
[[ $(git -C "$SUCCESS_TARGET" rev-parse HEAD) == "$expected_commit" ]]
[[ $(git -C "$SUCCESS_TARGET" config --get remote.origin.url) == "https://github.com/RegionallyFamous/one-bit-bureau.git" ]]
grep -Fq "setup:--adopt-plugin --verified-release $expected_commit --yes" "$MOCK_LOG"
grep -Fq "Verified One-Bit Bureau $TAG bundle: sha256:" "$WORK/success.log"

echo "== tampering is rejected before Omarchy or the target changes"
TAMPER="$WORK/tamper"
make_package "$TAMPER" 0
printf 'tamper\n' >>"$TAMPER/payload/one-bit-bureau-$TAG.bundle"
TAMPER_HOME="$WORK/tamper-home"
mkdir -p "$TAMPER_HOME"
: >"$MOCK_LOG"
if HOME="$TAMPER_HOME" PATH="$MOCK_BIN:$PATH" bash "$TAMPER/payload/install" >"$WORK/tamper.log" 2>&1; then
  echo "verified installer accepted a tampered bundle" >&2
  exit 1
fi
[[ ! -e $TAMPER_HOME/.config/omarchy/plugins/$PLUGIN_ID ]]
[[ ! -s $MOCK_LOG ]]
grep -Fq "Git bundle SHA-256 does not match" "$WORK/tamper.log"

echo "== setup failure removes the checkout created by the transaction"
FAILURE="$WORK/failure"
make_package "$FAILURE" 23
FAILURE_HOME="$WORK/failure-home"
mkdir -p "$FAILURE_HOME"
: >"$MOCK_LOG"
if HOME="$FAILURE_HOME" PATH="$MOCK_BIN:$PATH" bash "$FAILURE/payload/install" >"$WORK/failure.log" 2>&1; then
  echo "verified installer survived a setup failure" >&2
  exit 1
fi
[[ ! -e $FAILURE_HOME/.config/omarchy/plugins/$PLUGIN_ID ]]
grep -Fq "Rollback: removing the verified plugin checkout" "$WORK/failure.log"
grep -Fq "installation rolled back after an error" "$WORK/failure.log"

bash -n "$ROOT/release/install" "$ROOT/scripts/build-release-artifact"
echo "One-Bit Bureau verified release installer tests passed."
