#!/bin/bash
# Checks every case in the regression catalogue (docs/regression) has a test: a unit test
# (Tests/ExpanseTests, `@Test("AREA-NN …")`) for each case marked unit, and a unit test or an
# end-to-end case (Tests/Integration, `Case("AREA-NN", …)`) for each case marked manual.
# Prints the counts, then any case without one, and fails if there are any.
set -euo pipefail
cd "$(dirname "$0")/.."

unit_tests=$(grep -rhoE '@Test\("[A-Z]+-[0-9]+' Tests/ExpanseTests | sed 's/@Test("//' | sort -u)
e2e_cases=$(grep -rhoE 'Case\("[A-Z]+-[0-9]+"' Tests/Integration/Sources | sed 's/Case("//; s/"//' | sort -u)

missing=0 total=0 unit=0 manual=0 with_unit=0 with_e2e=0
for f in docs/regression/*.md; do
  [[ $f == */README.md || $f == */coverage.md ]] && continue
  # Each case: its ID and how its Automate line says to test it.
  while IFS='|' read -r id how; do
    total=$((total + 1))
    has_unit=$(grep -qx "$id" <<<"$unit_tests" && echo 1 || echo 0)
    has_e2e=$(grep -qx "$id" <<<"$e2e_cases" && echo 1 || echo 0)
    [[ $has_unit == 1 ]] && with_unit=$((with_unit + 1))
    [[ $has_e2e == 1 ]] && with_e2e=$((with_e2e + 1))
    if [[ $how == unit* ]]; then
      unit=$((unit + 1))
      [[ $has_unit == 1 ]] || { echo "no unit test: $id"; missing=$((missing + 1)); }
    else
      manual=$((manual + 1))
      [[ $has_unit == 1 || $has_e2e == 1 ]] || { echo "no test: $id"; missing=$((missing + 1)); }
    fi
  done < <(awk '/^## [A-Z]+-[0-9]+ /{id=$2} /\*\*Automate:\*\*/{sub(/.*\*\*Automate:\*\* */, ""); print id "|" $0}' "$f")
done

echo "$total cases ($unit unit, $manual manual): $with_unit with unit tests, $with_e2e with end-to-end cases, $missing without a test"
[[ $missing == 0 ]]
