#!/bin/bash
# Script to remove the example counter feature from the project
set -e

echo "🧹 Removing example counter feature..."

# 1. Remove directories
rm -rf lib/features/counter
rm -rf test/features/counter
echo "   ✓ Feature folders deleted"

# 2. Update service_locator.dart
if [ -f "lib/core/di/service_locator.dart" ]; then
    # Remove imports
    sed -i '/import.*counter/d' lib/core/di/service_locator.dart
    # Remove registrations
    sed -i '/ICounterLocalDataSource/d' lib/core/di/service_locator.dart
    sed -i '/ICounterRepository.*CounterRepository/d' lib/core/di/service_locator.dart
    sed -i '/CounterService/d' lib/core/di/service_locator.dart
    sed -i '/CounterCubit/d' lib/core/di/service_locator.dart
    echo "   ✓ DI registrations removed"
fi

# 3. Update route_constants.dart
if [ -f "lib/core/router/route_constants.dart" ]; then
    sed -i '/static const String counter/d' lib/core/router/route_constants.dart
    echo "   ✓ Route constants updated"
fi

# 4. Update app_router.dart
if [ -f "lib/core/router/app_router.dart" ]; then
    # Remove import
    sed -i '/import.*counter_screen.dart/d' lib/core/router/app_router.dart
    # Remove GoRoute block for counter. This is a bit tricky with sed, 
    # but we can look for the specific pattern.
    sed -i '/GoRoute(/{:a;N;/path: Routes.counter/!ba;d}' lib/core/router/app_router.dart 2>/dev/null || true
    echo "   ✓ Router updated"
fi

# 5. Remove button from home_screen.dart
if [ -f "lib/features/home/presentation/screens/home_screen.dart" ]; then
    # Remove the FilledButton.icon that navigates to counter
    sed -i '/FilledButton.icon(/{:a;N;/Routes.counter/!ba;d}' lib/features/home/presentation/screens/home_screen.dart 2>/dev/null || true
    # Remove the helper text below it
    sed -i '/A demo feature showing BLoC state management/d' lib/features/home/presentation/screens/home_screen.dart 2>/dev/null || true
    echo "   ✓ Home screen cleaned up"
fi

# 6. Update app_test.dart
if [ -f "test/app_test.dart" ]; then
    sed -i '/import.*counter/d' test/app_test.dart
    sed -i '/class MockCounterCubit/d' test/app_test.dart
    sed -i '/late MockCounterCubit/d' test/app_test.dart
    sed -i '/registerFallbackValue(const CounterState())/d' test/app_test.dart
    sed -i '/mockCounterCubit = MockCounterCubit()/d' test/app_test.dart
    # Remove stubs block
    sed -i '/when(() => mockCounterCubit.state)/d' test/app_test.dart
    sed -i '/when(() => mockCounterCubit.stream)/d' test/app_test.dart
    sed -i '/when(() => mockCounterCubit.close())/d' test/app_test.dart
    sed -i '/getIt.registerFactory<CounterCubit>/d' test/app_test.dart
    echo "   ✓ Integration tests cleaned up"
fi

echo "✅ Counter feature removal complete!"
