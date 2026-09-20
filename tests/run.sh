#!/bin/bash

set -euo pipefail

# Single entry point for this repo's self-checks. CI (harness-skills'
# reusable skill-check.yml) runs this file when it exists. Each lib/*.sh
# that ships a --self-test gets one line here, as does each skills/*/tests/
# script; the assertions themselves stay next to the code they cover.

cd -- "$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash skills/add-ai-metrics/lib/ai-metrics.sh --self-test
bash skills/kanban-bootstrap/tests/host.sh
bash skills/label-bootstrap/tests/verdict.sh
