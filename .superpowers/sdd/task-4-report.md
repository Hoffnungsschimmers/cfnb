# Task 4 Report: LatencyFilter 加 maxKeep 上限 (缺陷 B6)

## Status
✅ DONE

## Commit
`5ec10958d749c209835d534200ca63be758b377a` — "feat(latency): cap kept nodes with maxKeep"

## TDD Steps
1. 在 `test/core/latency/latency_test.dart` 的 `LatencyFilter.run` group 末尾追加 `respects maxKeep cap` 测试。
2. 运行确认编译错误：`No named parameter with the name 'maxKeep'` ✅（失败预期）。
3. 在 `lib/core/latency/latency_filter.dart`：
   - 签名新增 `int maxKeep = 200,`（位于 `int speedCap = 300,` 之后）。
   - `withinMax` 排序后新增 `final capped = withinMax.take(maxKeep).toList();`
   - 后续 `withinMax` 全部替换为 `capped`：带宽测速守卫、good 过滤、pool 回落、keptResults。
4. 运行测试：全部通过（8 + 0 失败）✅。
5. `flutter analyze`：No issues found ✅。

## Test Summary
```
00:00 +8: All tests passed!
```
- parseEndpoint (3)
- nodeCountry / nodeSource (1)
- latencyProbeAll (2)
- LatencyFilter.run: cutoff (1) + maxKeep cap (1)
