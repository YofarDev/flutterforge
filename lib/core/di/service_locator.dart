import 'package:get_it/get_it.dart';

import '../../features/counter/counter_module.dart';
import '../../features/counter/data/datasources/counter_local_datasource.dart';
import '../../features/home/data/datasources/home_remote_datasource.dart';
import '../../features/home/home_module.dart';

final GetIt getIt = GetIt.instance;

/// Registers the application dependency graph.
///
/// App-wide infrastructure (HTTP client, storage, ...) is registered here
/// first; each feature then registers itself through its module. `fgen` adds
/// new modules at the marker. The overrides replace data-source seams only,
/// for the real-component flow tests.
Future<void> setupServiceLocator({
  ICounterLocalDataSource? counterLocalDataSourceOverride,
  IHomeRemoteDataSource? homeRemoteDataSourceOverride,
}) async {
  registerHomeFeature(getIt, remoteDataSource: homeRemoteDataSourceOverride);
  registerCounterFeature(
    getIt,
    localDataSource: counterLocalDataSourceOverride,
  );
  // fgen:register-features
}
