import 'package:hive/hive.dart';

import '../../domain/entities/watch_record.dart';

/// [WatchRecord] 在 Hive 中的类型编号。
///
/// 约束：全局唯一（0~223），且**一旦发布不可更改**——已落盘的数据
/// 通过该编号反查适配器，改动会导致旧数据无法读取。
const int kWatchRecordTypeId = 7;

/// `WatchRecord` 的 Hive 适配器（**手写**）。
///
/// 为什么手写而不用 `hive_generator` + `build_runner`？
/// ------------------------------------------------------------------
/// 1. 免代码生成：本项目不含任何 `.g.dart`，`flutter pub get` 后即可编译，
///    不需要额外执行 `dart run build_runner build`；
/// 2. 字段演进可控：`WatchRecord.fromMap` 已兼容旧字段名
///    （`poster` / `episode_name` / `position`），历史数据无需迁移脚本；
/// 3. 模型保持纯 Dart：[WatchRecord] 不依赖 Hive，`domain` 层零外部依赖。
///
/// 存储形态：一个扁平 `Map<String, dynamic>`（见 `WatchRecord.toMap`）。
/// 相比按字段逐个 `readInt`/`readString`，Map 形态对新增字段天然宽容
/// —— 少一个键就用默认值，不会抛 `RangeError`。
class WatchRecordAdapter extends TypeAdapter<WatchRecord> {
  const WatchRecordAdapter();

  @override
  int get typeId => kWatchRecordTypeId;

  @override
  WatchRecord read(BinaryReader reader) {
    final raw = reader.readMap();
    return WatchRecord.fromMap(raw);
  }

  @override
  void write(BinaryWriter writer, WatchRecord obj) {
    writer.writeMap(obj.toMap());
  }
}
