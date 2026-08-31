#!/bin/bash
set -euo pipefail
node --test tests/*.test.js
bash tests/helper.test.sh
bash tests/focus-window.test.sh
bash tests/application-identity-metadata.test.sh
