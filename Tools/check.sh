#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/MemoBooksChecks.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
if [[ "${1:-}" == "--ai" ]]; then
  report="${2:-$PWD/ai-evaluation.json}"
  xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macos26.0" \
    -module-cache-path "$work_dir/modules" \
    MemoBooks/Services/DraftValidation.swift MemoBooks/Models/LedgerTypes.swift \
    MemoBooks/Models/ExpenseDraft.swift MemoBooks/Services/ExpenseParsingService.swift \
    Tests/AIEvaluation/Runner.swift -o "$work_dir/ai-evaluation"
  "$work_dir/ai-evaluation" Tests/AIEvaluation/cases.json "$report"
  exit 0
fi
if [[ $# -ne 0 ]]; then echo "Usage: $0 [--ai [report.json]]" >&2; exit 64; fi
xcrun swiftc -module-cache-path "$work_dir/modules" \
  MemoBooks/Services/DraftValidation.swift MemoBooks/Models/LedgerTypes.swift \
  Tests/main.swift -o "$work_dir/validation"
"$work_dir/validation"
xcrun swiftc -module-cache-path "$work_dir/modules" MemoBooks/Services/DraftValidation.swift Tests/InputHints/main.swift -o "$work_dir/input-hints"
"$work_dir/input-hints"
xcrun swiftc -module-cache-path "$work_dir/modules" \
  WatchApp/WatchOutbox.swift Tests/WatchOutbox/main.swift -o "$work_dir/outbox"
"$work_dir/outbox"
if ! xcodebuild -quiet -project Tests/StoreChecks/StoreChecks.xcodeproj -scheme StoreChecks \
  -configuration Debug -derivedDataPath "$work_dir/store-build" CODE_SIGNING_ALLOWED=NO build \
  > "$work_dir/build.log" 2>&1; then cat "$work_dir/build.log"; exit 1; fi
"$work_dir/store-build/Build/Products/Debug/LegacyFixture/LegacyFixture" "$work_dir/ledger.store"
"$work_dir/store-build/Build/Products/Debug/LedgerChecks/LedgerChecks" "$work_dir/ledger.store"
echo "All local checks passed. AI inference and paired-device delivery are separate checks."
