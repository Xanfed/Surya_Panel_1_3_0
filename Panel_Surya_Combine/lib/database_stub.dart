// Stub file untuk database interface - akan diganti oleh conditional imports
class DatabaseInterface {
  Future<void> init() async {
    throw UnimplementedError('DatabaseInterface must be implemented');
  }
  
  Future<void> insertLog(String title, String body, String time) async {
    throw UnimplementedError('insertLog must be implemented');
  }
  
  Future<List<Map<String, dynamic>>> getLogs() async {
    throw UnimplementedError('getLogs must be implemented');
  }

  Future<void> insertSchedule(String time, int duration, bool isActive) async {
    throw UnimplementedError('insertSchedule must be implemented');
  }

  Future<List<Map<String, dynamic>>> getSchedules() async {
    throw UnimplementedError('getSchedules must be implemented');
  }

  Future<void> updateSchedule(int id, String time, int duration, bool isActive) async {
    throw UnimplementedError('updateSchedule must be implemented');
  }

  Future<void> deleteSchedule(int id) async {
    throw UnimplementedError('deleteSchedule must be implemented');
  }
}

