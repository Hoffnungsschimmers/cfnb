p = "lib/core/latency/latency_filter.dart"
s = open(p, encoding="utf-8").read()
s = s.replace(
    "    Future<double?> Function(String ip, int port, Duration timeout)? probe,",
    "    Future<(double?, int)> Function(String ip, int port, Duration timeout, {int probes})? probe,",
)
open(p, "w", encoding="utf-8").write(s)
print("latency_filter probe type fixed")
