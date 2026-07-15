import '../models/api_result.dart';
import '../models/appointment_tree_model.dart';
import 'api_client.dart';

class AppointmentTreeService {
  AppointmentTreeService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<ApiResult<List<AppointmentTreeCategory>>> fetchTree() async {
    final result = await _apiClient.get('/appointment-tree');
    if (!result.success) {
      return ApiResult<List<AppointmentTreeCategory>>(
        success: false,
        message: result.message,
        statusCode: result.statusCode,
        raw: result.raw,
      );
    }

    final categories = parseAppointmentTree(result.data ?? result.raw);
    return ApiResult<List<AppointmentTreeCategory>>(
      success: true,
      message: result.message,
      data: categories,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }
}
