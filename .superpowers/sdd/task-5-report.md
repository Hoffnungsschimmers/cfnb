# Task 5: subscription_converter fetchFirstWorking 并发 + 逐 URL 日志

## Status: DONE

## Defect
B8 — `fetchFirstWorking` 串行依次尝试候选 URL，前面的 URL 阻塞后续，且任一 URL 抛异常会中断整个流程。

## Changes
- `lib/core/subscription/subscription_converter.dart`: 将 `fetchFirstWorking` 改为并发实现（`Future.wait` 同时发起全部候选 URL），每个 URL 用 `try/on Object` 包裹，单个失败不影响其他；返回首个能解析出节点链接的订阅原文，否则返回首个非空兜底。
- `test/core/subscription/subscription_converter_test.dart`: 新增 `fetchFirstWorking` group，验证「并发全部发起（callCount==3）」且「返回首个可用节点」。

逐 URL 错误日志已由调用方 `subscriptions_state._safeFetch` 覆盖，本任务无需额外日志。

## Commit
`c6811f12b3e35f0b6337c8d2e72115f122f8a59d`

## Test Summary
`flutter test test/core/subscription/subscription_converter_test.dart`
- All tests passed (10/10), 含新增 `fetchFirstWorking returns first url that yields nodes, concurrently`。

## Analyze
`flutter analyze lib/core/subscription/subscription_converter.dart`
- No issues found.
