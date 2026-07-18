# Task 3 Report — latency_prober 空源 + nodeCountry 修正

## Status: DONE

## Changes
- `lib/core/subscription/subscription_converter.dart` (`convertSubscriptions`):
  When resolved country code `cc` is empty, the node line is written without the `#`
  suffix: `final node = cc.isEmpty ? '$ip:${r.port}' : '$ip:${r.port}#$cc';`
- `test/core/subscription/subscription_converter_test.dart` (line ~89):
  Updated fallback assertion from `'2.2.2.2:443#UN'` to `'2.2.2.2:443'`.
- `latency_prober.dart`: NOT modified — `nodeCountry` already splits at `@` correctly.

## Commit
- `6fdaaae31d7f7b987b22a2e5fb4ab8049bcd9218` fix(subscription): omit country suffix when country unknown

## Test Summary
```
flutter test test/core/subscription/subscription_converter_test.dart test/core/latency/latency_test.dart
All tests passed! (17 tests)
```
