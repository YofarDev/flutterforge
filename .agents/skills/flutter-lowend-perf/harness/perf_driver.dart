// Copy to <app>/test_driver/perf_driver.dart.
// Host side of `flutter drive`: writes the take's reportData to
// build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(timeout: const Duration(minutes: 15));
