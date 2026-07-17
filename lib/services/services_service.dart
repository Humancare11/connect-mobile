import '../models/api_result.dart';
import '../models/service_model.dart';
import 'api_client.dart';

class ServicesService {
  ServicesService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<ApiResult<List<ServiceModel>>> fetchServices() async {
    final result = await _apiClient.get('/services');
    if (!result.success) {
      return ApiResult<List<ServiceModel>>(
        success: false,
        message: result.message,
        statusCode: result.statusCode,
        raw: result.raw,
      );
    }

    final services = parseServices(result.data ?? result.raw);
    return ApiResult<List<ServiceModel>>(
      success: true,
      message: result.message,
      data: services,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }
}
