import Foundation
import Capacitor
import MapKit
import CoreLocation

/**
 * Custom annotation class that extends MKPointAnnotation to support additional properties
 * for marker customization including icon URLs and expiry color indicators.
 *
 * Properties:
 * - iconUrl: Optional URL string for custom marker icons
 * - expiryColor: Optional color string ("red", "yellow", "green") to indicate content expiry status
 */
class CustomPointAnnotation: MKPointAnnotation {
    var iconUrl: String?
    var expiryColor: String?
}

@objc(appleMapsSdkPlugin)
public class appleMapsSdkPlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, MKMapViewDelegate {
    var mapView: MKMapView?
    var locationManager: CLLocationManager?
    var userCircle: MKCircle?
    private var annotations: [String: CustomPointAnnotation] = [:]
    
    public let identifier = "appleMapsSdkPlugin"
    public let jsName = "appleMapsSdk"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "initAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hideAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setValuesAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCenterPoint", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setZoomLevel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addCircle", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeCircle", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearMarkers", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "closeAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAppleMapsVisible", returnType: CAPPluginReturnPromise)
    ]

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve(["value": value])
    }

    @objc func initAppleMaps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            // If already initialized return sucess
            if self.mapView != nil {
                call.resolve(["status": "success"])
                return
            }
            
            // Location Manager Setup
            self.locationManager = CLLocationManager()
            self.locationManager?.delegate = self
            self.locationManager?.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            self.locationManager?.requestWhenInUseAuthorization()
            
            if CLLocationManager.locationServicesEnabled() {
                self.locationManager?.startUpdatingLocation()
                call.resolve(["status": "success"])
            } else {
                call.reject("Location services are not enabled")
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        guard self.mapView == nil else {
            manager.stopUpdatingLocation()
            return
        }
        
        let coordinates = CLLocationCoordinate2D(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let region = MKCoordinateRegion(
            center: coordinates,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        // Use full screen dimensions for map view
        guard let viewController = bridge?.viewController else {
            call?.reject("View controller not available")
            manager.stopUpdatingLocation()
            return
        }
        
        let frame = viewController.view.bounds
        let mapView = MKMapView(frame: frame)
        self.mapView = mapView
        
        // Enable custom annotation rendering and clustering support
        mapView.delegate = self
        
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = true
        mapView.isHidden = true
        
        if let viewController = bridge?.viewController {
            viewController.view.addSubview(mapView)
        }
        
        manager.stopUpdatingLocation()
    }

    @objc func showAppleMaps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.mapView == nil {
                call.reject("Map is not initialized. Please call initAppleMaps first.")
                return
            }
            
            self.mapView?.isHidden = false
            call.resolve(["status": "success"])
        }
    }

    @objc func hideAppleMaps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.mapView == nil {
                call.reject("Map is not initialized. Please call initAppleMaps first.")
                return
            }
            
            self.mapView?.isHidden = true
            call.resolve(["status": "success"])
        }
    }

    @objc func closeAppleMaps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            // Location Manager clean up
            self.locationManager?.stopUpdatingLocation()
            self.locationManager?.delegate = nil
            self.locationManager = nil
            
            self.mapView?.removeFromSuperview()
            self.mapView = nil
            
            call.resolve(["status": "success"])
        }
    }

    @objc func isAppleMapsVisible(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.mapView == nil {
                call.resolve(["status": 0])  // not initialized
            } else if self.mapView?.isHidden ?? true {
                call.resolve(["status": 1])  // not visible
            } else {
                call.resolve(["status": 2])  // visible
            }
        }
    }

    @objc func setValuesAppleMaps(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let dataPoints = call.getArray("dataPoints") as? [[String: Any]] else {
                call.reject("DataPoints are required")
                return
            }

            if self.mapView == nil {
                call.reject("Map is not initialized. Please call initAppleMaps first.")
                return
            }

            self.mapView?.removeAnnotations(self.mapView?.annotations ?? [])
            
            // Parse and add annotations from dataPoints array
            for point in dataPoints {
                print(point)
                if let lat = point["latitude"] as? Double,
                   let lon = point["longitude"] as? Double,
                   let label = point["label"] as? String {
                    
                    let annotation = CustomPointAnnotation()
                    annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    annotation.title = label
                    
                    // Support custom icon URL for marker personalization
                    if let iconUrl = point["iconUrl"] as? String {
                        annotation.iconUrl = iconUrl
                    }
                    
                    // Support expiry color for visual status indication (red/yellow/green)
                    if let expiryColor = point["expiryColor"] as? String {
                        annotation.expiryColor = expiryColor
                    }
                    
                    // Überprüfe, ob "startDate" und "endDate" vorhanden sind und ob sie sich unterscheiden
                    if let startDate = point["startDate"] as? String, let endDate = point["endDate"] as? String {
                        if startDate == endDate {
                            // Wenn beide gleich sind, zeige nur ein Datum
                            annotation.subtitle = "\(startDate):"
                        } else {
                            // Wenn sie unterschiedlich sind, zeige beide an
                            annotation.subtitle = "\(startDate) - \(endDate):"
                        }
                    }
                    
                    // Überprüfe, ob "description" einen Wert hat
                    if let descriptionEvent = point["description"] as? String, !descriptionEvent.isEmpty {
                        // Füge die Beschreibung hinzu, wenn vorhanden
                        if annotation.subtitle != nil {
                            annotation.subtitle? += " \(descriptionEvent)"
                        } else {
                            annotation.subtitle = descriptionEvent
                        }
                    }
                    
                    self.mapView?.addAnnotation(annotation)
                }
            }


            call.resolve(["status": "success"])
        }
    }
    
    func randomColor() -> UIColor {
            return UIColor(
                red: .random(in: 0...1),
                green: .random(in: 0...1),
                blue: .random(in: 0...1),
                alpha: 1.0
            )
        }
    
    /**
     * MKMapViewDelegate method for custom marker rendering with clustering support.
     *
     * This method handles both individual markers and cluster annotations:
     * - Individual markers: Colored based on expiryColor property (red/yellow/green)
     * - Cluster markers: Purple badges with count of grouped markers
     *
     * Clustering is automatically managed by MapKit when clusteringIdentifier is set.
     *
     * @param mapView The map view requesting the annotation view
     * @param annotation The annotation object to represent
     * @return MKAnnotationView configured for the annotation, or nil for user location
     */
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Don't customize user location marker
        if annotation is MKUserLocation {
            return nil
        }
        
        // Handle cluster annotations (grouped markers)
        if let cluster = annotation as? MKClusterAnnotation {
            let identifier = "Cluster"
            var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if clusterView == nil {
                clusterView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                clusterView?.canShowCallout = true
            } else {
                clusterView?.annotation = annotation
            }
            
            // Generate dynamic cluster image with member count
            let count = cluster.memberAnnotations.count
            clusterView?.image = generateClusterImage(count: count)
            
            return clusterView
        }
        
        // Handle individual custom markers
        guard let customAnnotation = annotation as? CustomPointAnnotation else {
            return nil
        }
        
        let identifier = "CustomMarker"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
        
        if annotationView == nil {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = true
            // Enable clustering - markers with same identifier will be automatically grouped
            annotationView?.clusteringIdentifier = "whisperCluster"
        } else {
            annotationView?.annotation = annotation
        }
        
        // Apply color based on expiry status
        if let expiryColor = customAnnotation.expiryColor {
            switch expiryColor.lowercased() {
            case "red":
                annotationView?.markerTintColor = UIColor.red
            case "yellow":
                annotationView?.markerTintColor = UIColor.systemYellow
            case "green":
                annotationView?.markerTintColor = UIColor.systemGreen
            default:
                annotationView?.markerTintColor = UIColor.systemBlue
            }
        }
        
        return annotationView
    }
    
    /**
     * Generates a cluster marker image with count badge.
     *
     * Creates a circular purple badge with white border and centered count text.
     * Size scales dynamically based on count (larger numbers = larger badge).
     *
     * @param count Number of markers in the cluster
     * @return UIImage representing the cluster badge
     */
    private func generateClusterImage(count: Int) -> UIImage {
        // Dynamic sizing based on count
        let baseSize: CGFloat = 40
        let maxSize: CGFloat = 60
        let countDigits = String(count).count
        let size = min(maxSize, baseSize + CGFloat(countDigits - 1) * 8)
        
        let finalSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: finalSize)
        
        return renderer.image { context in
            // Draw circular background
            let rect = CGRect(origin: .zero, size: finalSize)
            let circlePath = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            
            // Fill with purple color
            UIColor.systemPurple.setFill()
            circlePath.fill()
            
            // Draw white border
            UIColor.white.setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()
            
            // Draw count text centered
            let text = "\(count)"
            let fontSize: CGFloat = size > 50 ? 20 : 16
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (finalSize.width - textSize.width) / 2,
                y: (finalSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    /**
     * Set map zoom level by adjusting the visible region.
     *
     * @param zoom Zoom level (approximate conversion from web map zoom)
     * @param animated Whether to animate the zoom change
     */
    @objc func setZoomLevel(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            guard let zoom = call.getDouble("zoom") else {
                call.reject("Zoom level is required")
                return
            }
            
            let animated = call.getBool("animated") ?? true
            
            // Convert web zoom to MapKit span (rough approximation)
            // Web zoom 14 ≈ 0.05 degrees span
            // Each zoom level doubles/halves the visible area
            let baseSpan = 0.05
            let zoomFactor = pow(2.0, 14.0 - zoom)
            let span = baseSpan * zoomFactor
            
            let region = MKCoordinateRegion(
                center: mapView.region.center,
                span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
            )
            
            mapView.setRegion(region, animated: animated)
            call.resolve(["status": "success"])
        }
    }
    
    /**
     * Add a circle overlay to the map (used for user radius visualization).
     *
     * @param latitude Center latitude
     * @param longitude Center longitude
     * @param radius Radius in meters
     * @param strokeColor Hex color for circle border
     * @param fillColor Hex color for circle fill (supports rgba)
     * @param strokeWidth Border width in pixels
     */
    @objc func addCircle(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            guard let latitude = call.getDouble("latitude"),
                  let longitude = call.getDouble("longitude"),
                  let radius = call.getDouble("radius") else {
                call.reject("latitude, longitude, and radius are required")
                return
            }
            
            // Remove existing circle if present
            if let existingCircle = self.userCircle {
                mapView.removeOverlay(existingCircle)
            }
            
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let circle = MKCircle(center: center, radius: radius)
            
            self.userCircle = circle
            mapView.addOverlay(circle)
            
            call.resolve(["status": "success", "circleId": "user-circle"])
        }
    }
    
    /**
     * Remove the user circle overlay from the map.
     */
    @objc func removeCircle(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            if let circle = self.userCircle {
                mapView.removeOverlay(circle)
                self.userCircle = nil
            }
            
            call.resolve(["status": "success"])
        }
    }
    
    /**
     * Remove all markers from the map.
     */
    @objc func clearMarkers(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
            self.annotations.removeAll()
            
            call.resolve(["status": "success"])
        }
    }
    
    /**
     * MKMapViewDelegate method for rendering circle overlays.
     *
     * Renders user radius circle with custom colors.
     */
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circle = overlay as? MKCircle {
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 1.0)
            renderer.fillColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 0.3)
            renderer.lineWidth = 2
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
