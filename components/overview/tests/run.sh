#!/bin/bash

set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
node --test ./*.test.js
bash ./move-helper.test.sh
