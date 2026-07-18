# Task 9 Report — settings_fields dead groups + settings_page unused methods

**Status:** COMPLETED (analyze clean; test `settings_results_test.dart` FAILS — see note)

**Commit:** `a49d45fa7d00c6dacdc99d268e3b750c7e9c46d2`

## Changes
- `lib/features/settings/settings_fields.dart`: replaced entire `settingsFields` const with only the 5 live groups (订阅转换, 延迟优选, 带宽测速, GitHub 推送, 外观). All dead-field groups removed.
- `lib/features/settings/settings_page.dart`:
  - Removed unused methods `_slider`, `_doubleSlider`, `_textList`.
  - Fixed `for (final c in _ctl.values) c.dispose();` → `for (final c in _ctl.values) { c.dispose(); }`.

## Analyze
`flutter analyze lib/features/settings` → **No issues found!**

## Test
`flutter test test/features/settings_results_test.dart` → **FAILED** (2 of 5 tests).

The failures are pre-existing test assertions that reference now-removed dead keys:
- `settingsFields covers original SETTINGS_FIELDS keys` expects `PRE_FILTER_PORT_ENABLED`, `TCP_PROBES`, `MIN_SUCCESS_RATE`, `TEST_AVAILABILITY`, `BANDWIDTH_WORKERS`, `USE_GLOBAL_MODE`, `GLOBAL_TOP_N`, `QUALITY_SPEED_WEIGHT`, `CF_ENABLED`, `CF_API_TOKEN`, `AUTO_SCHEDULE_ENABLED` to be present. These are exactly the dead keys this task removes.
- `settingsFields includes node pool / github sections` expects `ASN_SOURCES` and `ADDITIONAL_SOURCES`, also removed dead keys.

Per task instructions, this is a test bug (the test pins obsolete dead keys); it was **reported, not modified**. The test needs updating to assert the live field keys instead. `parseResultLines` tests (3) still pass; `normalizeDraft` test passes.

## Recommendation
Update `test/features/settings_results_test.dart` to assert only the live keys (SUB_CONVERT_ENABLED, SUB_LATENCY_PROBES, SUB_SPEED_ENABLED, GITHUB_REPO, GUI_THEME, etc.) so the suite reflects the cleaned config.

## Test Fixed (follow-up)
**Status:** COMPLETED

**Commit:** `2fa16e5e4d5eaf85e996f3320f5a2a6ecf608369`

- Replaced `covers original SETTINGS_FIELDS keys` with `covers live SETTINGS_FIELDS keys`: asserts 12 live keys present + 11 dead keys absent.
- Renamed `includes node pool / github sections` → `includes github + theme sections`; removed `ASN_SOURCES` / `ADDITIONAL_SOURCES` assertions, kept GITHUB_REPO / GITHUB_BRANCH / GUI_THEME.
- Kept `normalizeDraft` test unchanged.

`flutter test test/features/settings_results_test.dart` → **All 5 tests passed.**
