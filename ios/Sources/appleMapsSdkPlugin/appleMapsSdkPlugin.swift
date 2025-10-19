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
 * - markerSize: Optional size in pixels for the marker (default 60)
 * - whisperId: Unique identifier for this marker (for navigation/interaction)
 */
class CustomPointAnnotation: MKPointAnnotation {
    var iconUrl: String?
    var initials: String?
    var avatarColor: String?
    var expiryColor: String?
    var markerSize: CGFloat = 60
    var whisperId: String?
    var isClickable: Bool = true
}

@objc(appleMapsSdkPlugin)
public class appleMapsSdkPlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, MKMapViewDelegate {
    var mapView: MKMapView?
    var locationManager: CLLocationManager?
    var userCircle: MKCircle?
    private var annotations: [String: CustomPointAnnotation] = [:]
    private var mapTopOffset: CGFloat = 0
    private var mapHeightOffset: CGFloat = 0
    private var hapticGenerator: UIImpactFeedbackGenerator?
    
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
            
            // Get optional positioning parameters from JS (in pixels)
            self.mapTopOffset = CGFloat(call.getDouble("topOffset") ?? 0.0)
            self.mapHeightOffset = CGFloat(call.getDouble("heightOffset") ?? 0.0)
            
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
        
        // Position map view with custom offsets for header/footer
        guard let viewController = bridge?.viewController else {
            manager.stopUpdatingLocation()
            return
        }
        
        guard let webView = self.bridge?.webView else {
            manager.stopUpdatingLocation()
            return
        }
        
        // Calculate frame: start below header (topOffset), extend to bottom of screen
        let safeArea = viewController.view.safeAreaInsets
        let topY = safeArea.top + self.mapTopOffset
        
        // When using native UI (mapHeightOffset = 0), fill entire screen below header
        // When using web UI with footer (mapHeightOffset > 0), subtract footer space
        let bottomSpace = self.mapHeightOffset > 0 ? (safeArea.bottom + self.mapHeightOffset) : 0
        let availableHeight = viewController.view.bounds.height - topY - bottomSpace
        
        let frame = CGRect(
            x: 0,
            y: topY,
            width: viewController.view.bounds.width,
            height: availableHeight
        )
        
        let mapView = MKMapView(frame: frame)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.mapView = mapView
        
        // Prepare haptic generator for instant feedback (no delay on first tap)
        self.hapticGenerator = UIImpactFeedbackGenerator(style: .light)
        self.hapticGenerator?.prepare()
        
        // Enable custom annotation rendering and clustering support
        mapView.delegate = self
        
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = true
        mapView.isHidden = true
        
        // Insert map BELOW the webview
        viewController.view.insertSubview(mapView, belowSubview: webView)

        // Disable user interaction on Apple’s blue location dot (so whispers above it can be tapped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.mapView?.subviews.forEach { subview in
                if NSStringFromClass(type(of: subview)).contains("UserLocationView") {
                    subview.isUserInteractionEnabled = false
                }
            }
        }
        
        // Make webview background transparent so map shows through
        webView.isOpaque = false
        webView.backgroundColor = .clear
        if let scrollView = webView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.backgroundColor = .clear
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
                    
                    // Support initials for text-based avatar fallback
                    if let initials = point["initials"] as? String {
                        annotation.initials = initials
                    }
                    
                    // Support avatar background color for initials
                    if let avatarColor = point["avatarColor"] as? String {
                        annotation.avatarColor = avatarColor
                    }
                    
                    // Support expiry color for visual status indication (red/yellow/green)
                    if let expiryColor = point["expiryColor"] as? String {
                        annotation.expiryColor = expiryColor
                    }
                    
                    // Support custom marker size (default 60px)
                    if let markerSize = point["markerSize"] as? Double {
                        annotation.markerSize = CGFloat(markerSize)
                    }
                    
                    // Support unique whisper ID for navigation on tap 
                    if let whisperId = point["whisperId"] as? String {
                        annotation.whisperId = whisperId
                    }
                    // Support isClickable flag for markers that should not trigger interactions
                    if let isClickable = point["isClickable"] as? Bool {
                        annotation.isClickable = isClickable
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
     * - Individual markers: Custom circular image with profile photo and colored border
     * - Cluster markers: Purple badges with count of grouped markers
     *
     * Clustering is automatically managed by MapKit when clusteringIdentifier is set.
     *
     * @param mapView The map view requesting the annotation view
     * @param annotation The annotation object to represent
     * @return MKAnnotationView configured for the annotation, or nil for user location
     */
    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        // Use default blue dot for user location BUT disable callout
        if annotation is MKUserLocation {
            return nil
        }

        // Custom marker handling
        guard let customAnnotation = annotation as? CustomPointAnnotation else {
            return nil
        }

        let identifier = "CustomMarker"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = false         // no Apple balloon
            annotationView?.clusteringIdentifier = nil     // disable native clustering
            annotationView?.displayPriority = .required    // Higher priority than user location
            annotationView?.isEnabled = true               // Enable tap
        } else {
            annotationView?.annotation = annotation
        }

        let borderColor = getBorderColorFromExpiry(customAnnotation.expiryColor)
        let markerSize = customAnnotation.markerSize
        
        // Parse avatarColor from hex string
        let avatarBgColor = customAnnotation.avatarColor.flatMap { parseHexColor($0) }

        // set fallback image (with initials if available)
        annotationView?.image = self.generateCircularMarkerImage(
            profileImage: nil,
            initials: customAnnotation.initials,
            avatarColor: avatarBgColor,
            borderColor: borderColor,
            size: markerSize
        )

        // load profile image (asynchronous)
        if let iconUrl = customAnnotation.iconUrl, !iconUrl.isEmpty {
            loadImageAsync(from: iconUrl) { [weak annotationView] image in
                guard let annotationView = annotationView else { return }
                annotationView.image = self.generateCircularMarkerImage(
                    profileImage: image,
                    initials: nil,
                    avatarColor: nil,
                    borderColor: borderColor,
                    size: markerSize
                )
            }
        }

        return annotationView
    }
    
    private func getBorderColorFromExpiry(_ expiryColor: String?) -> UIColor {
        guard let color = expiryColor?.lowercased() else {
            return UIColor.systemGreen
        }
        
        switch color {
        case "red":
            return UIColor(red: 244/255, green: 67/255, blue: 54/255, alpha: 1.0)
        case "yellow":
            return UIColor(red: 255/255, green: 235/255, blue: 59/255, alpha: 1.0)
        case "green":
            return UIColor(red: 76/255, green: 175/255, blue: 80/255, alpha: 1.0)
        default:
            return UIColor.systemBlue
        }
    }
    
    private func generateCircularMarkerImage(profileImage: UIImage?, initials: String?, avatarColor: UIColor?, borderColor: UIColor, size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))
            let circlePath = UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            
            // Clip to circle
            circlePath.addClip()
            
            if let profileImage = profileImage {
                // Draw profile photo
                profileImage.draw(in: rect.insetBy(dx: 3, dy: 3))
            } else if let initials = initials, !initials.isEmpty, initials != "?" {
                // Draw initials with background color (like header design)
                let backgroundColor = avatarColor ?? UIColor(red: 0.95, green: 0.32, blue: 0.31, alpha: 1.0)
                backgroundColor.setFill()
                circlePath.fill()
                
                // Draw white text initials
                let fontSize = size * 0.4
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                
                let textSize = (initials as NSString).size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (size - textSize.width) / 2,
                    y: (size - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                
                (initials as NSString).draw(in: textRect, withAttributes: attributes)
            } else {
                // Fallback: generate default avatar with user icon (generic)
                let backgroundColor = avatarColor ?? UIColor(red: 0.61, green: 0.64, blue: 0.69, alpha: 1.0) // #9CA3AF
                backgroundColor.setFill()
                circlePath.fill()
                
                // Draw default user icon (head + body circles)
                UIColor.white.setFill()
                
                // Head circle
                let headRadius = (size - 6) * 0.15
                let headCenter = CGPoint(x: size / 2, y: (size - 6) * 0.35 + 3)
                let headCircle = UIBezierPath(ovalIn: CGRect(
                    x: headCenter.x - headRadius,
                    y: headCenter.y - headRadius,
                    width: headRadius * 2,
                    height: headRadius * 2
                ))
                headCircle.fill()
                
                // Body circle
                let bodyRadius = (size - 6) * 0.25
                let bodyCenter = CGPoint(x: size / 2, y: (size - 6) * 0.75 + 3)
                let bodyCircle = UIBezierPath(ovalIn: CGRect(
                    x: bodyCenter.x - bodyRadius,
                    y: bodyCenter.y - bodyRadius,
                    width: bodyRadius * 2,
                    height: bodyRadius * 2
                ))
                bodyCircle.fill()
            }
            
            // Draw border
            borderColor.setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()
        }
    }
    
    private func parseHexColor(_ hex: String) -> UIColor? {
        var hexFormatted = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexFormatted = hexFormatted.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexFormatted).scanHexInt64(&rgb) else {
            return nil
        }
        
        let length = hexFormatted.count
        let r, g, b, a: CGFloat
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    
    private func loadImageAsync(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(image)
            }
        }.resume()
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
    
    @objc func setCenterPoint(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            guard let latitude = call.getDouble("latitude"),
                  let longitude = call.getDouble("longitude") else {
                call.reject("latitude and longitude are required")
                return
            }
            
            let animated = call.getBool("animated") ?? true
            
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = MKCoordinateRegion(
                center: center,
                span: mapView.region.span
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
                print("🔵 [MapKit] Removing existing circle")
                mapView.removeOverlay(existingCircle)
            }
            
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let circle = MKCircle(center: center, radius: radius)
            
            print("🔵 [MapKit] Adding circle at: \(latitude), \(longitude) with radius: \(radius)m")
            self.userCircle = circle
            mapView.addOverlay(circle)
            print("✅ [MapKit] Circle overlay added to map")
            
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
     * MKMapViewDelegate method for handling annotation selection (tap).
     *
     * Triggers when user taps on a marker. Notifies JS layer via bridge event.
     */
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Ignore user location taps
        guard let annotation = view.annotation as? CustomPointAnnotation else {
            return
        }
        
        // INSTANT deselect - no animation for maximum speed
        view.isSelected = false
        
        // INSTANT haptic feedback using pre-prepared generator (NO delay)
        self.hapticGenerator?.impactOccurred()
        self.hapticGenerator?.prepare()  // Prepare for next tap
        
        // Notify JS layer about marker tap
        var tapData: [String: Any] = [
            "latitude": annotation.coordinate.latitude,
            "longitude": annotation.coordinate.longitude,
            "title": annotation.title ?? ""
        ]
        
        // Add marker ID and isClickable if available
        if let whisperId = annotation.whisperId {
            tapData["whisperId"] = whisperId
        }
        tapData["isClickable"] = annotation.isClickable
        
        notifyListeners("onMarkerTap", data: tapData)
        
        print("📍 [MapKit] Marker tapped - ID: \(annotation.whisperId ?? "none"), isClickable: \(annotation.isClickable)")
    }
    
    /**
     * MKMapViewDelegate method to block user location selection.
     *
     * Prevents callout popup and any interaction with user location marker.
     */
    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        // Block user location deselection handling (prevent any UI feedback)
    }
    
    /**
     * MKMapViewDelegate method for rendering circle overlays.
     *
     * Renders user radius circle with custom colors.
     */
    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let circle = overlay as? MKCircle {
            print("🔵 [MapKit] Rendering circle overlay - radius: \(circle.radius)m")
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 1.0)
            renderer.fillColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 0.3)
            renderer.lineWidth = 2
            print("✅ [MapKit] Circle renderer created with stroke color and fill")
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}
