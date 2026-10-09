import 'dart:ffi' as ffi;

// 1. Define the C++ signature
typedef CalculateDeliveryTimeC = ffi.Double Function(
    ffi.Double, ffi.Double, ffi.Double, ffi.Double);

// 2. Define the Dart signature
typedef CalculateDeliveryTimeDart = double Function(
    double, double, double, double);

void main() {
  // 3. Load the native shared library we just compiled
  final libraryPath = '../librouting_engine.so';
  print('Loading C++ Library: $libraryPath');
  final dylib = ffi.DynamicLibrary.open(libraryPath);

  // 4. Look up the exact memory address of our function
  final calculateDelivery = dylib
      .lookup<ffi.NativeFunction<CalculateDeliveryTimeC>>('calculate_delivery_time')
      .asFunction<CalculateDeliveryTimeDart>();

  print('Calling Native C++ routing engine...\n');
  
  // Coordinates: Warehouse (Los Angeles) to Customer (Las Vegas)
  double lat1 = 34.0522;
  double lon1 = -118.2437;
  double lat2 = 36.1699;
  double lon2 = -115.1398;
  
  // Let's measure how fast the Dart -> C++ boundary is
  final stopwatch = Stopwatch()..start();
  
  // 5. Execute C++ from Dart
  double minutes = calculateDelivery(lat1, lon1, lat2, lon2);
  
  stopwatch.stop();

  print('--------------------------------------------------');
  print('Estimated Delivery Time: ${minutes.toStringAsFixed(1)} minutes');
  print('C++ Execution Time: ${stopwatch.elapsedMicroseconds} microseconds');
  print('--------------------------------------------------');
  print('Zero serialization overhead. Pure native performance.');
}
