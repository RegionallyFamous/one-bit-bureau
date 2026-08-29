#!/bin/bash
set -euo pipefail
node --test tests/*.test.js
bash tests/helper.test.sh
