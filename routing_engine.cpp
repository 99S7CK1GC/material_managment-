#include <stdint.h>
#include <math.h>

// We use extern "C" so Dart can find the exact function names without C++ name mangling
extern "C" {

    // A fast, native function to calculate estimated delivery time
    // Takes the coordinates of the pickup (lat1, lon1) and dropoff (lat2, lon2)
    double calculate_delivery_time(double lat1, double lon1, double lat2, double lon2) {
        // Haversine formula to calculate the great-circle distance between two GPS points
        double dLat = (lat2 - lat1) * M_PI / 180.0;
        double dLon = (lon2 - lon1) * M_PI / 180.0;
        
        // Convert latitudes to radians
        lat1 = (lat1) * M_PI / 180.0;
        lat2 = (lat2) * M_PI / 180.0;

        double a = pow(sin(dLat / 2), 2) + pow(sin(dLon / 2), 2) * cos(lat1) * cos(lat2);
        double rad = 6371.0; // Earth's radius in kilometers
        double c = 2 * asin(sqrt(a));
        
        double distance_km = rad * c;
        
        // Assume an average delivery speed of 40 km/h in the city
        double estimated_hours = distance_km / 40.0;
        
        // Return the estimated time in minutes
        return estimated_hours * 60.0; 
    }

}
