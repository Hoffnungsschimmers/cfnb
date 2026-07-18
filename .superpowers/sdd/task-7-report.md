# Task 7 Report

**Status:** DONE (with one plan inconsistency resolved in favor of the TDD test contract)

**Commit:** `ece7df7` — `fix(push): only .top files; share direct dio; use subLatencyProbes`

## Files changed
- `lib/core/github/github_push.dart`
- `lib/features/subscriptions/subscriptions_state.dart`
- `test/core/github/github_push_test.dart`

## Test summary
`flutter test test/core/github/github_push_test.dart` → **All 5 tests passed** (including the new `isPushable only .top files` group).

## Changes implemented
1. **`.top` push guard (A4/B11/B12):** Added `static bool GithubPush.isPushable(String file)`; `SubscriptionsNotifier.pushFile` early-returns `(false,0,'仅支持推送后缀为 _top.txt 的优选结果文件（当前：$file）')` when `!GithubPush.isPushable(file)`.
2. **Shared Dio (A4):** Added `static Dio GithubPush.directDio()` (no `findProxy` override → system proxy; UA + timeouts). `subscriptions_state` now uses `final _dio = GithubPush.directDio();` and drops `_configureDio()`, `_resolveProxy()`, the `io_adapter` import, and the `_configureDio()` constructor call.
3. **Deprecated API (B11):** Replaced `onHttpClientCreate` with `createHttpClient` in the `GithubPush` constructor (returns `HttpClient` with `findProxy='DIRECT'` + `userAgent`). Added `import 'dart:io';` required by `HttpClient`.
4. **Latency probes (B7):** `runLatency` now passes `probes: cfg.subLatencyProbes` instead of hardcoded `3`.
5. `_httpFetch` headers now include `'Accept': '*/*'`. Removed unused `app_logger.dart` import (only `subLoggerProvider` from `providers.dart` is used).

## Plan inconsistency (resolved)
The plan's literal `isPushable` implementation `file.toLowerCase().endsWith('.top')` **contradicts its own test**, which asserts `GithubPush.isPushable('addressesapi_top.txt')` is `true`. `addressesapi_top.txt` ends with `.txt`, not `.top`, so `endsWith('.top')` would FAIL that test. The test (the binding TDD contract for Task 7) distinguishes `addressesapi_top.txt` (pushable) from `addressesapi.txt` / `ip.txt` (not pushable) — the marker is the `_top` name segment. Implemented `endsWith('_top.txt')` to satisfy the test and aligned the guard message to say `_top.txt`. This matches the real default `subLatencyOutputFile` (`addressesapi_top.txt`).

## Cross-file compile errors observed (belong to later tasks — NOT this task)
The full project does not compile because Tasks 8/9 have not run yet (deleted `AppConfig` fields referenced by `settings_fields.dart`, `results_page.dart`, etc.). `flutter analyze` on the two edited files shows NO errors/warnings in `subscriptions_state.dart`. The only issues reported in `github_push.dart` are pre-existing and non-task:
- `implementation_imports` (line 5, `io_adapter.dart`) — the plan explicitly keeps this import for `IOHttpClientAdapter`.
- `use_null_aware_elements` (line 100) — pre-existing `on DioException` handler, not introduced by Task 7.

These are out of scope for Task 7 and will be resolved (or accepted) by later tasks.
