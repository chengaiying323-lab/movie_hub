import 'dart:async';
import 'dart:collection';

/// 轻量信号量（并发闸门）。
///
/// 多源聚合搜索会在同一时刻向 N 个数据源发起请求。若不限流：
/// - iOS 端会因 FD 耗尽 / ATS 队列拥塞导致大面积超时；
/// - Windows 端则可能被目标站的 WAF 判定为 CC 攻击而封 IP。
///
/// 因此所有出网请求统一经由信号量管控。
class Semaphore {
  Semaphore(this.maxPermits) : assert(maxPermits > 0, 'maxPermits 必须大于 0');

  final int maxPermits;

  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get activeCount => _active;
  int get pendingCount => _waiters.length;

  /// 以受控并发执行 [task]，无论成功与否都归还许可。
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxPermits) {
      _active++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // 直接把许可"转交"给队列头部的等待者，_active 保持不变。
      _waiters.removeFirst().complete();
      return;
    }
    _active--;
  }
}
