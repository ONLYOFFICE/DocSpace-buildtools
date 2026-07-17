#!/bin/bash
# Run browser smoke tests from the host against the DocSpace VM (forwarded localhost:8080).
# Optional env: LICENSE (content) or LICENSE_FILE (path) — wizard license (standalone requires one).

set -e
cd "$(dirname "$0")"

if ! vagrant status | grep -q "running"; then
  echo "VM is not running, skipping smoke test"
  exit 0
fi

PIP_BREAK_SYSTEM_PACKAGES=1 pip install -q --disable-pip-version-check -r ../smoke/requirements.txt

# Capture the exit code separately so a failure can be reported as a readable annotation, not just "exit code 1"
set +e
SERVER_URL=http://localhost:8080 python3 -m pytest ../smoke/test_docspace_smoke.py -v -s | tee smoke-output.log
exit_code=${PIPESTATUS[0]}
set -e

if [ "$exit_code" -ne 0 ]; then
  grep '^FAILED ' smoke-output.log | sed 's/^FAILED /::error::Smoke test failed: /'
fi
rm -f smoke-output.log
exit "$exit_code"
