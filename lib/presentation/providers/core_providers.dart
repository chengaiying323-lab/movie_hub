import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/http_service.dart';
import '../../core/utils/semaphore.dart';
import '../../data/datasources/local/source_local_datasource.dart';
import '../../data/datasources/local/watch_history_local_datasource.dart';
import '../../data/datasources/remote/source_remote_datasource.dart';
import '../../data/parsers/parser_registry.dart';
import '../../data/repositories/movie_repository_impl.dart';
import '../../data/repositories/watch_history_repository_impl.dart';
import '../../data/services/home_feed_service.dart';
import '../../data/services/search_aggregator.dart';
import '../../data/services/source_manager.dart';
import '../../domain/repositories/movie_repository.dart';
import '../../domain/repositories/source_repository.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../../domain/usecases/get_movie_detail_usecase.dart';
import '../../domain/usecases/search_movies_usecase.dart';

/// 依赖注入容器（Riverpod Provider 图）。
///
/// 分层原则：presentation 只依赖 domain 抽象（如 [MovieRepository]），
/// data 层实现通过本文件装配。这样替换实现（例如换成本地 mock）只需改这里。

// ── core 层 ───────────────────────────────────────────────

final httpServiceProvider = Provider<HttpService>((ref) {
  final service = HttpService();
  ref.onDispose(service.dispose);
  return service;
});

/// 全局搜索并发闸门：所有多源聚合共用，避免多条搜索叠加时并发失控。
final searchGateProvider = Provider<Semaphore>((ref) {
  return Semaphore(AppConstants.maxConcurrentSources);
});

// ── data 层 ───────────────────────────────────────────────

final parserRegistryProvider = Provider<ParserRegistry>(
  (ref) => ParserRegistry(),
);

final sourceLocalDataSourceProvider = Provider<SourceLocalDataSource>(
  (ref) => SourceLocalDataSource(),
);

final remoteSubscriptionFetcherProvider =
    Provider<RemoteSubscriptionFetcher>((ref) {
  return SourceRemoteDataSource(http: ref.watch(httpServiceProvider));
});

final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepositoryImpl(
    local: ref.watch(sourceLocalDataSourceProvider),
    remote: ref.watch(remoteSubscriptionFetcherProvider),
  );
});

final searchAggregatorProvider = Provider<SearchAggregator>((ref) {
  return SearchAggregator(
    http: ref.watch(httpServiceProvider),
    registry: ref.watch(parserRegistryProvider),
    gate: ref.watch(searchGateProvider),
  );
});

final sourceManagerProvider = Provider<SourceManager>((ref) {
  return SourceManager(
    repository: ref.watch(sourceRepositoryProvider),
    aggregator: ref.watch(searchAggregatorProvider),
    registry: ref.watch(parserRegistryProvider),
    http: ref.watch(httpServiceProvider),
  );
});

final movieRepositoryProvider = Provider<MovieRepository>((ref) {
  return MovieRepositoryImpl(
    sourceRepository: ref.watch(sourceRepositoryProvider),
    aggregator: ref.watch(searchAggregatorProvider),
    registry: ref.watch(parserRegistryProvider),
    http: ref.watch(httpServiceProvider),
  );
});

// ── 用户观影记录（想看 / 正在看 / 已看） ────────────────────

/// Hive Box 的持有者。
///
/// 只暴露数据源而非直接暴露 Box：Box 是懒开的，让所有写入都经过
/// [WatchHistoryRepository] 这一层，才能保证"容量淘汰"等策略不被绕过。
final watchHistoryLocalDataSourceProvider =
    Provider<WatchHistoryLocalDataSource>((ref) {
  return WatchHistoryLocalDataSource();
});

final watchHistoryRepositoryProvider = Provider<WatchHistoryRepository>((ref) {
  return WatchHistoryRepositoryImpl(
    local: ref.watch(watchHistoryLocalDataSourceProvider),
  );
});

// ── 首页装配 ──────────────────────────────────────────────

final homeFeedServiceProvider = Provider<HomeFeedService>((ref) {
  return HomeFeedService(
    movieRepository: ref.watch(movieRepositoryProvider),
    sourceRepository: ref.watch(sourceRepositoryProvider),
  );
});

// ── domain 用例 ───────────────────────────────────────────

final searchMoviesUseCaseProvider = Provider<SearchMoviesUseCase>(
  (ref) => SearchMoviesUseCase(ref.watch(movieRepositoryProvider)),
);

final getMovieDetailUseCaseProvider = Provider<GetMovieDetailUseCase>(
  (ref) => GetMovieDetailUseCase(ref.watch(movieRepositoryProvider)),
);
