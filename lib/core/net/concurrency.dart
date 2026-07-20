import 'dart:async';

/// 简易信号量，限制并发数（避免上千源/域名瞬时打满 socket 或 DNS）。
class Semaphore {
  Semaphore(this._count);
  int _count;
  final _queue = <Completer<void>>[];
  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _count++;
    }
  }
}
