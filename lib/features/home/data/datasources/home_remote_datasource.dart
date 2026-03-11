import '../models/home_data_dto.dart';

abstract class IHomeRemoteDataSource {
  Future<HomeDataDto> getHomeData();
}

class HomeRemoteDataSource implements IHomeRemoteDataSource {
  @override
  Future<HomeDataDto> getHomeData() async {
    // Simulate network delay
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // In a real app, this would use http or dio to fetch JSON and parse it
    return HomeDataDto(
      welcomeMessage: 'Welcome to the app!',
      lastUpdated: DateTime.now().toIso8601String(),
    );
  }
}
