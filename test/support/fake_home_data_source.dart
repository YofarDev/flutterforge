import 'package:my_flutter_app/features/home/data/datasources/home_remote_datasource.dart';
import 'package:my_flutter_app/features/home/data/models/home_data_dto.dart';

/// Scripted fake for the home network seam, used by the real-component flow
/// tests: each call to [getHomeData] consumes the next enqueued response
/// producer. Producers return plain data (including malformed payloads) or
/// complete via [Completer]s — no timers, no real network.
class ScriptedHomeDataSource implements IHomeRemoteDataSource {
  final List<Future<HomeDataDto> Function()> _script =
      <Future<HomeDataDto> Function()>[];
  int calls = 0;

  void enqueue(Future<HomeDataDto> Function() response) {
    _script.add(response);
  }

  @override
  Future<HomeDataDto> getHomeData() {
    if (calls >= _script.length) {
      throw StateError('No scripted home response for call #$calls');
    }
    return _script[calls++]();
  }
}
