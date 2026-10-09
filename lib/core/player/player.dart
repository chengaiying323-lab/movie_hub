/// 播放内核统一出口。
///
/// 上层只 `import '../core/player/player.dart';`，
/// **不要**直接 import `media_kit` / `media_kit_video`。
/// 这样将来替换内核（AVPlayer / fvp / 自研）时，改动面被限制在本目录内。
library;

export 'media_kit_player_engine.dart';
export 'playback_source.dart';
export 'playback_state.dart';
export 'player_bootstrap.dart';
export 'player_config.dart';
export 'player_engine.dart';
