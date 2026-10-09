import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/core/di/service_locator.dart';
import 'package:my_flutter_app/features/counter/data/datasources/counter_local_datasource.dart';
import 'package:my_flutter_app/features/counter/data/repositories/counter_repository_impl.dart';
import 'package:my_flutter_app/features/counter/domain/repositories/counter_repository.dart';
import 'package:my_flutter_app/features/counter/domain/services/counter_service.dart';
import 'package:my_flutter_app/features/counter/presentation/bloc/counter_cubit.dart';
import 'package:my_flutter_app/features/home/data/datasources/home_remote_datasource.dart';
import 'package:my_flutter_app/features/home/data/repositories/home_repository_impl.dart';
import 'package:my_flutter_app/features/home/domain/repositories/home_repository.dart';
import 'package:my_flutter_app/features/home/presentation/bloc/home_cubit.dart';

/// DI smoke test — every registration must resolve. This catches wiring
/// mistakes (missing registration, wrong lifetime, unresolvable constructor
/// arguments) at test time instead of at first navigation.
///
/// Update this file whenever you add a registration.
void main() {
  tearDown(() {
    getIt.reset();
  });

  test('registers and resolves every dependency', () async {
    await setupServiceLocator();

    expect(getIt<ICounterLocalDataSource>(), isA<CounterLocalDataSource>());
    expect(getIt<IHomeRemoteDataSource>(), isA<HomeRemoteDataSource>());
    expect(getIt<ICounterRepository>(), isA<CounterRepository>());
    expect(getIt<IHomeRepository>(), isA<HomeRepository>());
    expect(getIt<CounterService>(), isA<CounterService>());
  });

  test('cubits resolve as factories (fresh instances per request)', () async {
    await setupServiceLocator();

    final CounterCubit counterCubitFirst = getIt<CounterCubit>();
    final CounterCubit counterCubitSecond = getIt<CounterCubit>();
    final HomeCubit homeCubitFirst = getIt<HomeCubit>();
    final HomeCubit homeCubitSecond = getIt<HomeCubit>();
    addTearDown(counterCubitFirst.close);
    addTearDown(counterCubitSecond.close);
    addTearDown(homeCubitFirst.close);
    addTearDown(homeCubitSecond.close);

    expect(identical(counterCubitFirst, counterCubitSecond), isFalse);
    expect(identical(homeCubitFirst, homeCubitSecond), isFalse);
  });
}
