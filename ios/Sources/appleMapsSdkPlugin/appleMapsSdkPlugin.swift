import Foundation
import Capacitor
import MapKit
import CoreLocation

/**
 * Custom annotation class that extends MKPointAnnotation to support addition        // Insert map BELOW the webview
        viewController.view.insertSubview(mapView, belowSubview: webView)
        
        // Make webview background transparent so map shows through
        webView.isOpaque = false
        webView.backgroundColor = .clear
        if let scrollView = webView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView { for marker customization including icon URLs and expiry color indicators.
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
    var opacity: CGFloat = 1.0  // Opacity for out-of-range whispers (0.0-1.0, default 1.0)
    var originalCoordinate: CLLocationCoordinate2D?
}

/**
 * Custom cluster annotation for grouping nearby whispers.
 * Shows first whisper's avatar with "+X more" text below.
 */
class WhisperClusterAnnotation: MKPointAnnotation {
    var whisperAnnotations: [CustomPointAnnotation] = []
    var mainWhisper: CustomPointAnnotation?
    var moreText: String = "more" // Translated text from JS
    
    var count: Int {
        return whisperAnnotations.count
    }
}

@objc(appleMapsSdkPlugin)
public class appleMapsSdkPlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, MKMapViewDelegate {
    var mapView: MKMapView?
    var locationManager: CLLocationManager?
    var userCircle: MKCircle?
    var mockUserLocationAnnotation: MKPointAnnotation?  // MOCK user location marker
    var isMockModeActive: Bool = false  // Track if mock GPS is active
    private var annotations: [String: CustomPointAnnotation] = [:]
    private var clusterAnnotations: [WhisperClusterAnnotation] = []
    private var mapTopOffset: CGFloat = 0
    private var mapHeightOffset: CGFloat = 0
    private var hapticGenerator: UIImpactFeedbackGenerator?
    private var moreWhispersTranslation: String = "more"
    private var clusteringThreshold: Double = 50
    private var lastClusteredZoomLevel: Double = 0
    private var cachedWhisperIds: Set<String> = [] // Track zoom level of last clustering
    
    // AUTO-SYNC VARIABLES: Track current radius for automatic updates
    private var currentUserRadius: Double? = nil  // Saved radius when circle is active
    private var autoSyncEnabled: Bool = false     // Only sync when circle is active
    
    public let identifier = "appleMapsSdkPlugin"
    public let jsName = "appleMapsSdk"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "initAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "showAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hideAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setValuesAppleMaps", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCenterPoint", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setCenterAndZoom", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setZoomLevel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "addCircle", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeCircle", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearMarkers", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setMockUserLocation", returnType: CAPPluginReturnPromise),  // NEW: For TikTok demo
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
        
        // If map is not initialized yet, create it
        guard self.mapView == nil else {
            // MAP IS INITIALIZED: Handle location updates for auto-sync
            self.handleLocationUpdate(location)
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
        
        // Add tap gesture BEFORE MapKit processes touches (instant response)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        tapGesture.cancelsTouchesInView = false  // Allow MapKit to still receive touches
        tapGesture.delaysTouchesBegan = false     // NO delay on touch begin
        tapGesture.delaysTouchesEnded = false     // NO delay on touch end
        mapView.addGestureRecognizer(tapGesture)
        
        // Enable custom annotation rendering and clustering support
        mapView.delegate = self
        
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = true  // Default: enabled (will be disabled if mock is activated)
        mapView.isHidden = true
        
        // Insert map BELOW the webview
        viewController.view.insertSubview(mapView, belowSubview: webView)

        // Disable user interaction on Apple’s blue location dot (so whispers above it can be tapped)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
            
            // Get translation for "more" from JS
            if let moreText = call.getString("moreWhispersTranslation") {
                self.moreWhispersTranslation = moreText
            }
            
            // Get clustering threshold from JS (optional)
            if let threshold = call.getDouble("clusteringThreshold") {
                self.clusteringThreshold = threshold
            }

            // GRANULAR DIFFING: Identify NEW, REMOVED, and UNCHANGED whispers
            var incomingWhisperIds = Set<String>()
            for point in dataPoints {
                if let id = point["whisperId"] as? String {
                    incomingWhisperIds.insert(id)
                }
            }
            
            // Full cache hit - zero changes in whisper IDs
            // BUT still need to update visual properties (opacity, expiryColor) that may have changed
            if incomingWhisperIds == self.cachedWhisperIds && !incomingWhisperIds.isEmpty {
                // Build fast lookup map for incoming data
                var incomingDataMap: [String: [String: Any]] = [:]
                for point in dataPoints {
                    if let id = point["whisperId"] as? String {
                        incomingDataMap[id] = point
                    }
                }
                
                // Update existing annotations' visual properties WITHOUT removing/re-adding
                guard let mapView = self.mapView else { 
                    call.resolve(["status": "cached"])
                    return 
                }
                
                for annotation in mapView.annotations {
                    var whisperId: String? = nil
                    
                    if let customAnnotation = annotation as? CustomPointAnnotation {
                        whisperId = customAnnotation.whisperId
                    } else if let clusterAnnotation = annotation as? WhisperClusterAnnotation {
                        whisperId = clusterAnnotation.mainWhisper?.whisperId
                    }
                    
                    guard let id = whisperId, let incomingData = incomingDataMap[id] else { continue }
                    
                    // Update opacity on annotation view (visual change only)
                    if let view = mapView.view(for: annotation) {
                        let newOpacity = (incomingData["opacity"] as? Double) ?? 1.0
                        view.alpha = CGFloat(newOpacity)
                    }
                    
                    // Update stored opacity on annotation object
                    if let customAnnotation = annotation as? CustomPointAnnotation {
                        customAnnotation.opacity = CGFloat((incomingData["opacity"] as? Double) ?? 1.0)
                        if let expiryColor = incomingData["expiryColor"] as? String {
                            customAnnotation.expiryColor = expiryColor
                        }
                    }
                }
                
                call.resolve(["status": "cached"])
                return
            }
            
            // Calculate diff sets
            let newWhisperIds = incomingWhisperIds.subtracting(self.cachedWhisperIds)
            let removedWhisperIds = self.cachedWhisperIds.subtracting(incomingWhisperIds)
            let unchangedWhisperIds = incomingWhisperIds.intersection(self.cachedWhisperIds)
            
            
            // Update cache
            self.cachedWhisperIds = incomingWhisperIds
            
            // Clustering depends on ALL whispers, not just new ones
            // We must remove ALL annotations and re-cluster EVERYTHING when there are changes
            // This ensures clusters are calculated correctly with all whisper positions
            
            // Remove ALL whisper annotations (NOT user location, NOT mock location)
            self.mapView?.removeAnnotations(self.mapView?.annotations.filter { annotation in
                // Keep MKUserLocation (native GPS dot)
                if annotation is MKUserLocation { return false }
                
                // Keep mock location annotation (for TikTok demo)
                if let pointAnnotation = annotation as? MKPointAnnotation,
                   pointAnnotation.title == "MockUserLocation" {
                    return false
                }
                
                // Remove everything else (whispers, clusters)
                return true
            } ?? [])
            self.clusterAnnotations.removeAll()
            
            // Track whisper IDs to prevent duplicates
            var existingWhisperIds = Set<String>()
            
            // Parse and create annotations from ALL incoming dataPoints
            var whisperAnnotations: [CustomPointAnnotation] = []
            
            for point in dataPoints {
                if let lat = point["latitude"] as? Double,
                   let lon = point["longitude"] as? Double,
                   let label = point["label"] as? String {
                    
                    // Deduplicate by whisper ID
                    var whisperId: String? = nil
                    if let id = point["whisperId"] as? String {
                        whisperId = id
                        
                        // Skip if we've already added this whisper in THIS batch
                        if existingWhisperIds.contains(id) {
                            continue
                        }
                        existingWhisperIds.insert(id)
                    }
                    
                    let annotation = CustomPointAnnotation()
                    annotation.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    annotation.originalCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
                    if let id = whisperId {
                        annotation.whisperId = id
                    }
                    // Support isClickable flag for markers that should not trigger interactions
                    if let isClickable = point["isClickable"] as? Bool {
                        annotation.isClickable = isClickable
                    }
                    
                    // Support opacity for out-of-range whispers (0.0-1.0, default 1.0)
                    if let opacity = point["opacity"] as? Double {
                        annotation.opacity = CGFloat(opacity)
                    }
                    
                    // Date range handling
                    if let startDate = point["startDate"] as? String, let endDate = point["endDate"] as? String {
                        if startDate == endDate {
                            annotation.subtitle = "\(startDate):"
                        } else {
                            annotation.subtitle = "\(startDate) - \(endDate):"
                        }
                    }
                    
                    // Description handling
                    if let descriptionEvent = point["description"] as? String, !descriptionEvent.isEmpty {
                        if annotation.subtitle != nil {
                            annotation.subtitle? += " \(descriptionEvent)"
                        } else {
                            annotation.subtitle = descriptionEvent
                        }
                    }
                    
                    whisperAnnotations.append(annotation)
                }
            }
                        
            // CLUSTERING LOGIC: Re-cluster ALL whispers (clustering depends on ALL positions)
            let clusteredAnnotations = self.clusterNearbyWhispers(whisperAnnotations)
            
            // Add all clustered annotations to map
            self.mapView?.addAnnotations(clusteredAnnotations)

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
        // MOCK USER LOCATION VIEW for TikTok demo
        if let pointAnnotation = annotation as? MKPointAnnotation, pointAnnotation.title == "MockUserLocation" {
            let identifier = "MockUserLocationView"
            var userView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if userView == nil {
                userView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                userView?.canShowCallout = false
                userView?.isEnabled = false
                userView?.zPriority = .min

                let dotSize: CGFloat = 16
                let borderWidth: CGFloat = 2
                let glowRadius: CGFloat = 10
                let totalSize = dotSize + (borderWidth * 2) + (glowRadius * 2)

                let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalSize, height: totalSize))
                let image = renderer.image { ctx in
                    let center = CGPoint(x: totalSize / 2, y: totalSize / 2)
                    let blueColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                    let whiteColor = UIColor.white

                    let colors = [blueColor.withAlphaComponent(0.25).cgColor, UIColor.clear.cgColor] as CFArray
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                        ctx.cgContext.drawRadialGradient(
                            gradient,
                            startCenter: center,
                            startRadius: dotSize / 2,
                            endCenter: center,
                            endRadius: totalSize / 2,
                            options: .drawsAfterEndLocation
                        )
                    }

                    let dotRect = CGRect(
                        x: (totalSize - dotSize) / 2,
                        y: (totalSize - dotSize) / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.cgContext.setFillColor(blueColor.cgColor)
                    ctx.cgContext.fillEllipse(in: dotRect)

                    ctx.cgContext.setStrokeColor(whiteColor.cgColor)
                    ctx.cgContext.setLineWidth(borderWidth)
                    ctx.cgContext.strokeEllipse(in: dotRect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
                }

                userView?.image = image
                userView?.frame = CGRect(x: 0, y: 0, width: totalSize, height: totalSize)
                userView?.centerOffset = .zero
            }

            return userView
        }
        
        // CUSTOM USER LOCATION VIEW - Modern, clean design with NO tap interaction
        if annotation is MKUserLocation {
            let identifier = "CustomUserLocationView"
            var userView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if userView == nil {
                userView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                userView?.canShowCallout = false
                userView?.isEnabled = false
                userView?.zPriority = .min

                // ...existing user location rendering code...
                let dotSize: CGFloat = 16
                let borderWidth: CGFloat = 2
                let glowRadius: CGFloat = 10
                let totalSize = dotSize + (borderWidth * 2) + (glowRadius * 2)

                let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalSize, height: totalSize))
                let image = renderer.image { ctx in
                    let center = CGPoint(x: totalSize / 2, y: totalSize / 2)
                    let blueColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0)
                    let whiteColor = UIColor.white

                    let colors = [blueColor.withAlphaComponent(0.25).cgColor, UIColor.clear.cgColor] as CFArray
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                        ctx.cgContext.drawRadialGradient(
                            gradient,
                            startCenter: center,
                            startRadius: dotSize / 2,
                            endCenter: center,
                            endRadius: totalSize / 2,
                            options: .drawsAfterEndLocation
                        )
                    }

                    let dotRect = CGRect(
                        x: (totalSize - dotSize) / 2,
                        y: (totalSize - dotSize) / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.cgContext.setFillColor(blueColor.cgColor)
                    ctx.cgContext.fillEllipse(in: dotRect)

                    ctx.cgContext.setStrokeColor(whiteColor.cgColor)
                    ctx.cgContext.setLineWidth(borderWidth)
                    ctx.cgContext.strokeEllipse(in: dotRect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
                }

                userView?.image = image
                userView?.frame = CGRect(x: 0, y: 0, width: totalSize, height: totalSize)
                userView?.centerOffset = .zero
            }

            return userView
        }
        
        // CLUSTER ANNOTATION - Show main whisper avatar with "+X more" below
        if let clusterAnnotation = annotation as? WhisperClusterAnnotation {
            let identifier = "ClusterMarker"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
                annotationView?.isEnabled = true
                annotationView?.zPriority = .max
            } else {
                annotationView?.annotation = annotation
            }
            
            guard let mainWhisper = clusterAnnotation.mainWhisper else {
                return nil
            }
            
            let borderColor = getBorderColorFromExpiry(mainWhisper.expiryColor)
            let markerSize = mainWhisper.markerSize
            let avatarBgColor = mainWhisper.avatarColor.flatMap { parseHexColor($0) }
            
            // Render cluster image: avatar + "+X more" text below
            let count = clusterAnnotation.count
            let moreCount = count - 1
            let moreText = "+\(moreCount) \(clusterAnnotation.moreText)"
            
            annotationView?.image = self.generateClusterMarkerImage(
                profileImage: nil,
                initials: mainWhisper.initials,
                avatarColor: avatarBgColor,
                borderColor: borderColor,
                size: markerSize,
                moreText: moreText
            )
            
            let hasClickableWhisper = clusterAnnotation.whisperAnnotations.contains { $0.isClickable }
            let clusterOpacity: CGFloat = hasClickableWhisper ? 1.0 : (clusterAnnotation.whisperAnnotations.map { $0.opacity }.min() ?? 1.0)
            annotationView?.alpha = clusterOpacity
            
            // Load profile image asynchronously
            if let iconUrl = mainWhisper.iconUrl, !iconUrl.isEmpty {
                loadImageAsync(from: iconUrl) { [weak annotationView, weak clusterAnnotation] image in
                    guard let annotationView = annotationView else { return }
                    guard let clusterAnnotation = clusterAnnotation else { return }
                    annotationView.image = self.generateClusterMarkerImage(
                        profileImage: image,
                        initials: nil,
                        avatarColor: nil,
                        borderColor: borderColor,
                        size: markerSize,
                        moreText: moreText
                    )
                    // Re-apply opacity after async image load
                    let hasClickableWhisper = clusterAnnotation.whisperAnnotations.contains { $0.isClickable }
                    let clusterOpacity: CGFloat = hasClickableWhisper ? 1.0 : (clusterAnnotation.whisperAnnotations.map { $0.opacity }.min() ?? 1.0)
                    annotationView.alpha = clusterOpacity
                }
            }

            return annotationView
        }

        // INDIVIDUAL CUSTOM MARKER
        guard let customAnnotation = annotation as? CustomPointAnnotation else {
            return nil
        }

        let identifier = "CustomMarker"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

        if annotationView == nil {
            annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView?.canShowCallout = false
            annotationView?.clusteringIdentifier = nil
            annotationView?.displayPriority = .required
            annotationView?.isEnabled = true
            annotationView?.zPriority = .max
        } else {
            annotationView?.annotation = annotation
        }

        let borderColor = getBorderColorFromExpiry(customAnnotation.expiryColor)
        let markerSize = customAnnotation.markerSize
        let avatarBgColor = customAnnotation.avatarColor.flatMap { parseHexColor($0) }

        annotationView?.image = self.generateCircularMarkerImage(
            profileImage: nil,
            initials: customAnnotation.initials,
            avatarColor: avatarBgColor,
            borderColor: borderColor,
            size: markerSize
        )
        
        // Apply opacity for out-of-range whispers (0.0-1.0, default 1.0)
        annotationView?.alpha = customAnnotation.opacity

        if let iconUrl = customAnnotation.iconUrl, !iconUrl.isEmpty {
            loadImageAsync(from: iconUrl) { [weak annotationView, weak customAnnotation] image in
                guard let annotationView = annotationView else { return }
                guard let customAnnotation = customAnnotation else { return }
                annotationView.image = self.generateCircularMarkerImage(
                    profileImage: image,
                    initials: nil,
                    avatarColor: nil,
                    borderColor: borderColor,
                    size: markerSize
                )
                // Re-apply opacity after async image load
                annotationView.alpha = customAnnotation.opacity
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
    
    /**
     * Generate cluster marker image with "+X more" text below avatar.
     * IDENTICAL to MapComponent design: avatar on top, text below.
     */
    private func generateClusterMarkerImage(profileImage: UIImage?, initials: String?, avatarColor: UIColor?, borderColor: UIColor, size: CGFloat, moreText: String) -> UIImage {
        // Calculate total size: avatar + spacing + text height
        let avatarSize = size
        let textSpacing: CGFloat = 4
        let textFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: UIColor.white
        ]
        let textSize = (moreText as NSString).size(withAttributes: textAttributes)
        let totalHeight = avatarSize + textSpacing + textSize.height + 6  // +6 for text halo
        let totalWidth = max(avatarSize, textSize.width + 10)
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
        
        return renderer.image { context in
            let ctx = context.cgContext
            
            // 1. Draw avatar at top center
            let avatarX = (totalWidth - avatarSize) / 2
            let avatarRect = CGRect(x: avatarX, y: 0, width: avatarSize, height: avatarSize)
            let circlePath = UIBezierPath(ovalIn: avatarRect.insetBy(dx: 3, dy: 3))
            
            // Clip to circle
            circlePath.addClip()
            
            if let profileImage = profileImage {
                profileImage.draw(in: avatarRect.insetBy(dx: 3, dy: 3))
            } else if let initials = initials, !initials.isEmpty, initials != "?" {
                let backgroundColor = avatarColor ?? UIColor(red: 0.95, green: 0.32, blue: 0.31, alpha: 1.0)
                backgroundColor.setFill()
                circlePath.fill()
                
                let fontSize = avatarSize * 0.4
                let initialsAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                
                let initialsSize = (initials as NSString).size(withAttributes: initialsAttributes)
                let initialsRect = CGRect(
                    x: avatarX + (avatarSize - initialsSize.width) / 2,
                    y: (avatarSize - initialsSize.height) / 2,
                    width: initialsSize.width,
                    height: initialsSize.height
                )
                
                (initials as NSString).draw(in: initialsRect, withAttributes: initialsAttributes)
            } else {
                let backgroundColor = avatarColor ?? UIColor(red: 0.61, green: 0.64, blue: 0.69, alpha: 1.0)
                backgroundColor.setFill()
                circlePath.fill()
                
                // Default user icon
                UIColor.white.setFill()
                let headRadius = (avatarSize - 6) * 0.15
                let headCenter = CGPoint(x: avatarX + avatarSize / 2, y: (avatarSize - 6) * 0.35 + 3)
                let headCircle = UIBezierPath(ovalIn: CGRect(
                    x: headCenter.x - headRadius,
                    y: headCenter.y - headRadius,
                    width: headRadius * 2,
                    height: headRadius * 2
                ))
                headCircle.fill()
                
                let bodyRadius = (avatarSize - 6) * 0.25
                let bodyCenter = CGPoint(x: avatarX + avatarSize / 2, y: (avatarSize - 6) * 0.75 + 3)
                let bodyCircle = UIBezierPath(ovalIn: CGRect(
                    x: bodyCenter.x - bodyRadius,
                    y: bodyCenter.y - bodyRadius,
                    width: bodyRadius * 2,
                    height: bodyRadius * 2
                ))
                bodyCircle.fill()
            }
            
            // Reset clip for border
            ctx.resetClip()
            
            // Draw border
            borderColor.setStroke()
            circlePath.lineWidth = 3
            circlePath.stroke()
            
            // 2. Draw "+X more" text below avatar (IDENTICAL to MapComponent)
            let textY = avatarSize + textSpacing
            let textX = (totalWidth - textSize.width) / 2
            let textRect = CGRect(
                x: textX,
                y: textY,
                width: textSize.width,
                height: textSize.height
            )
            
            // Text halo (black outline for visibility)
            let haloAttributes: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: UIColor.black,
                .strokeColor: UIColor.black,
                .strokeWidth: -4.0  // Negative = fill + stroke
            ]
            (moreText as NSString).draw(in: textRect, withAttributes: haloAttributes)
            
            // Text foreground (white)
            (moreText as NSString).draw(in: textRect, withAttributes: textAttributes)
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
    
    @objc func setCenterAndZoom(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else {
                call.reject("Map is not initialized")
                return
            }
            
            guard let latitude = call.getDouble("latitude"),
                  let longitude = call.getDouble("longitude"),
                  let zoom = call.getDouble("zoom") else {
                call.reject("latitude, longitude, and zoom are required")
                return
            }
            
            let animated = call.getBool("animated") ?? true
            
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            
            // Convert web zoom to MapKit span (same logic as setZoomLevel)
            let baseSpan = 0.05
            let zoomFactor = pow(2.0, 14.0 - zoom)
            let span = baseSpan * zoomFactor
            
            let region = MKCoordinateRegion(
                center: center,
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
            
            // SAVE radius for auto-sync and enable automatic updates
            self.currentUserRadius = radius
            self.autoSyncEnabled = true
                        
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
            
            // DISABLE auto-sync when circle is removed
            self.autoSyncEnabled = false
            self.currentUserRadius = nil
            
            
            call.resolve(["status": "success"])
        }
    }
    
    /**
     * Set mock user location 
     * Creates a custom annotation that looks like the user location dot.
     * Pass latitude/longitude = 0 to DISABLE mock mode and restore native GPS.
     */
    @objc func setMockUserLocation(_ call: CAPPluginCall) {
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
            
            // DISABLE MOCK MODE if coordinates are (0, 0)
            if latitude == 0 && longitude == 0 {
                // Remove mock annotation
                if let existingMock = self.mockUserLocationAnnotation {
                    mapView.removeAnnotation(existingMock)
                    self.mockUserLocationAnnotation = nil
                }
                
                // Re-enable native user location dot
                mapView.showsUserLocation = true
                self.isMockModeActive = false
                
                // RESTART location manager for real GPS tracking
                self.locationManager?.startUpdatingLocation()
                
                call.resolve(["status": "mock_disabled"])
                return
            }
            
            // ENABLE MOCK MODE
            self.isMockModeActive = true
            
           
            self.locationManager?.stopUpdatingLocation()
            
            // FORCE DISABLE native user location dot (we're using mock)
            mapView.showsUserLocation = false
            
            // FORCE REMOVE native location view from map subviews
            mapView.subviews.forEach { subview in
                if NSStringFromClass(type(of: subview)).contains("UserLocationView") {
                    subview.removeFromSuperview()
                }
            }
            
            // Remove existing mock location if present
            if let existingMock = self.mockUserLocationAnnotation {
                mapView.removeAnnotation(existingMock)
            }
            
            // Create new mock location annotation
            let mockAnnotation = MKPointAnnotation()
            mockAnnotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            mockAnnotation.title = "MockUserLocation"  // Special identifier
            
            self.mockUserLocationAnnotation = mockAnnotation
            mapView.addAnnotation(mockAnnotation)
            
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

            // Remove ALL CustomPointAnnotation and WhisperClusterAnnotation
            let customAnnotations = mapView.annotations.filter { $0 is CustomPointAnnotation }
            let clusterAnnotations = mapView.annotations.filter { $0 is WhisperClusterAnnotation }
            let allWhisperAnnotations = customAnnotations + clusterAnnotations
            
            if !allWhisperAnnotations.isEmpty {
                mapView.removeAnnotations(allWhisperAnnotations)
            }

            // Clear internal tracking arrays
            self.annotations.removeAll()
            self.clusterAnnotations.removeAll()
            
          
            self.cachedWhisperIds.removeAll()            
            // Force MapKit to invalidate ALL reusable annotation views
            // This clears the internal cache that might be causing clustering issues
            let currentRegion = mapView.region
            let tempRegion = MKCoordinateRegion(
                center: currentRegion.center,
                span: MKCoordinateSpan(
                    latitudeDelta: currentRegion.span.latitudeDelta * 1.0001,
                    longitudeDelta: currentRegion.span.longitudeDelta * 1.0001
                )
            )
            mapView.setRegion(tempRegion, animated: false)
            mapView.setRegion(currentRegion, animated: false)
            
            // Final verification
            let remainingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        
            
            call.resolve(["status": "success"])
        }
    }
    
    /**
     * MKMapViewDelegate method for handling annotation selection (tap).
     *
     * DEPRECATED: Now using handleMapTap for instant response.
     * This method is kept as fallback but should rarely fire since handleMapTap processes taps first.
     */
    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        // Ignore user location taps
        guard let annotation = view.annotation as? CustomPointAnnotation else {
            return
        }
        
        // INSTANT deselect - prevent MapKit's selection animation
        view.isSelected = false
        
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
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 1.0)
            renderer.fillColor = UIColor(red: 0, green: 229/255, blue: 255/255, alpha: 0.3)
            renderer.lineWidth = 2
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
    
    /**
     * MKMapViewDelegate method for tracking map region changes.
     *
     * Shows/hides recenter button based on distance from user location.
     * If map center is more than 100m from user location, show button.
     * 
     * RE-CLUSTER ON ZOOM CHANGE: When zoom changes significantly (±1 level),
     * re-cluster with new dynamic threshold. Prevents performance issues by only
     * reclustering on meaningful zoom changes.
     */
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        guard let userLocation = mapView.userLocation.location else { return }
        
        let mapCenter = mapView.centerCoordinate
        let userCoordinate = userLocation.coordinate
        
        // Calculate distance between map center and user location
        let mapCenterLocation = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        let userCLLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let distance = mapCenterLocation.distance(from: userCLLocation)
        
        // Show recenter button if distance > 100m, hide if < 50m (hysteresis)
        let showThreshold: CLLocationDistance = 100
        let hideThreshold: CLLocationDistance = 50
        
        if distance > showThreshold {
            notifyListeners("showRecenterButton", data: [:])
        } else if distance < hideThreshold {
            notifyListeners("hideRecenterButton", data: [:])
        }
        
        // RE-CLUSTER on significant zoom change (±1 level = threshold changes)
        let currentZoom = self.getApproximateZoomLevel()
        let zoomDelta = abs(currentZoom - self.lastClusteredZoomLevel)
        
        // Only re-cluster if zoom changed by at least 1 level (threshold tier changes)
        if zoomDelta >= 1.0 && self.lastClusteredZoomLevel > 0 {
            self.reclusterWhispers()
        }
    }
    
    /**
     * INSTANT tap handler - processes touches BEFORE MapKit's didSelect delegate.
     * 
     * This method intercepts tap gestures at the UIView level, allowing us to:
     * 1. Fire haptic feedback immediately (< 16ms)
     * 2. Identify tapped annotation synchronously
     * 3. Notify JS layer without waiting for MapKit's selection pipeline
     * 
     * Result: 50-100ms faster than using didSelect alone.
     */
    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        guard let mapView = self.mapView else { return }
        
        let touchPoint = gesture.location(in: mapView)
        
        // INSTANT haptic feedback (BEFORE any processing)
        self.hapticGenerator?.impactOccurred()
        self.hapticGenerator?.prepare()
        
        // Check for cluster tap first (higher priority)
        for annotation in mapView.annotations {
            guard let clusterAnnotation = annotation as? WhisperClusterAnnotation else { continue }
            guard let annotationView = mapView.view(for: annotation) else { continue }
            
            let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
            
            // Get image size (avatar + text)
            let imageSize = annotationView.image?.size ?? CGSize(width: 60, height: 80)
            let expandedHitSize = imageSize.width * 1.5
            let hitRect = CGRect(
                x: annotationPoint.x - expandedHitSize / 2,
                y: annotationPoint.y - imageSize.height / 2,
                width: expandedHitSize,
                height: imageSize.height
            )
            
            if hitRect.contains(touchPoint) {
                // CLUSTER TAP: Calculate intelligent zoom to separate ALL whispers
                
                // Find max distance between any 2 whispers in cluster (bounding box)
                // Use ORIGINAL coordinates for accurate distance measurement
                var maxDistance: CLLocationDistance = 0
                let whispers = clusterAnnotation.whisperAnnotations
                
                for i in 0..<whispers.count {
                    for j in (i+1)..<whispers.count {
                        let coord1 = whispers[i].originalCoordinate ?? whispers[i].coordinate
                        let coord2 = whispers[j].originalCoordinate ?? whispers[j].coordinate
                        
                        let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
                        let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
                        let distance = loc1.distance(from: loc2)
                        maxDistance = max(maxDistance, distance)
                    }
                }
                
                // If whispers have identical/very close coordinates (< 5m apart),
                // artificially spread them in a circle so they become visible individually
                // MINIMAL SPREAD: Only 3-5m to keep whispers close to real location
                let threshold: CLLocationDistance = 5.0
                if maxDistance < threshold && whispers.count > 1 {
                    
                    // MINIMAL spread: 3m base + 0.5m per whisper (e.g., 2 whispers = 3.5m radius, 5 whispers = 5.5m)
                    // This keeps whispers VERY close to real location while making them tappable
                    let baseRadius: Double = 3.0  // Base 3m radius
                    let perWhisperOffset: Double = 0.5  // +0.5m per whisper
                    let spreadRadius = baseRadius + (perWhisperOffset * Double(whispers.count))
                    
                    let angleStep = 2.0 * .pi / Double(whispers.count)
                    
                    //  Use cluster's coordinate (centroid) as center, not first whisper
                    let centerCoord = clusterAnnotation.coordinate
                    
                    
                    for (index, whisper) in whispers.enumerated() {
                        let angle = Double(index) * angleStep
                        
                        // Convert meters to degrees (approximately)
                        // 1 degree latitude ≈ 111,000 meters
                        let deltaLat = (spreadRadius * sin(angle)) / 111000.0
                        let deltaLon = (spreadRadius * cos(angle)) / (111000.0 * cos(centerCoord.latitude * .pi / 180.0))
                        
                        // Update BOTH coordinate AND originalCoordinate
                        // This makes the spread PERMANENT so whispers stay separated after re-clustering
                        let newCoord = CLLocationCoordinate2D(
                            latitude: centerCoord.latitude + deltaLat,
                            longitude: centerCoord.longitude + deltaLon
                        )
                        whisper.coordinate = newCoord
                        whisper.originalCoordinate = newCoord  // Make spread permanent
                    }
                    
                    // Recalculate maxDistance after spread
                    maxDistance = spreadRadius * 2.0
                }
                
                // Calculate target zoom based on threshold tiers
                
                let targetZoom: Double
                if maxDistance > 200000 {
                    // Need zoom tier with threshold < maxDistance
                    // Zoom 8-10 has 50km threshold (too small for > 200km)
                    // Stay at zoom 6 (middle of 200km tier) - will need manual spread
                    targetZoom = 6.0
                } else if maxDistance > 50000 {
                    // 50km < distance <= 200km (e.g., Varese-Verona 150km)
                    // Target zoom 8-10 tier (50km threshold < 150km = SEPARATION)
                    targetZoom = 9.0  // Middle of tier
                } else if maxDistance > 10000 {
                    // 10km < distance <= 50km
                    // Target zoom 11-12 tier (10km threshold)
                    targetZoom = 11.5
                } else if maxDistance > 2000 {
                    // 2km < distance <= 10km
                    // Target zoom 13-14 tier (2km threshold)
                    targetZoom = 13.5
                } else if maxDistance > 500 {
                    // 500m < distance <= 2km
                    // Target zoom 15-16 tier (500m threshold)
                    targetZoom = 15.5
                } else if maxDistance > 200 {
                    // 200m < distance <= 500m
                    // Target zoom 17-18 tier (200m threshold)
                    targetZoom = 17.5
                } else if maxDistance > 50 {
                    // 50m < distance <= 200m
                    // Target zoom 18+ tier (50m threshold)
                    targetZoom = 18.5
                } else {
                    // Very close (< 50m) - zoom to building level
                    targetZoom = 19.0
                }
                
                // Convert target zoom to MKCoordinateSpan
                // Web zoom 14 = 0.05 degrees span
                let baseSpan = 0.05
                let zoomFactor = pow(2.0, 14.0 - targetZoom)
                let calculatedSpan = baseSpan * zoomFactor
                
                // Add 20% margin for comfortable separation
                let finalSpan = calculatedSpan * 1.2
                
                
                let region = MKCoordinateRegion(
                    center: clusterAnnotation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: finalSpan, longitudeDelta: finalSpan)
                )
                
                // Smooth zoom animation
                mapView.setRegion(region, animated: true)
                
                // After zoom, re-cluster whispers (will separate due to higher zoom + offset)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.reclusterWhispers()
                }
                
                return
            }
        }
        
        // Find tapped individual whisper (fast CGRect hit test)
        for annotation in mapView.annotations {
            guard let customAnnotation = annotation as? CustomPointAnnotation else { continue }
            guard let annotationView = mapView.view(for: annotation) else { continue }
            
            let annotationPoint = mapView.convert(annotation.coordinate, toPointTo: mapView)
            
            let markerSize = customAnnotation.markerSize
            let expandedHitSize = markerSize * 1.5
            let hitRect = CGRect(
                x: annotationPoint.x - expandedHitSize / 2,
                y: annotationPoint.y - expandedHitSize / 2,
                width: expandedHitSize,
                height: expandedHitSize
            )
            
            if hitRect.contains(touchPoint) {
                var tapData: [String: Any] = [
                    "latitude": customAnnotation.coordinate.latitude,
                    "longitude": customAnnotation.coordinate.longitude,
                    "title": customAnnotation.title ?? "",
                    "isClickable": customAnnotation.isClickable
                ]
                
                if let whisperId = customAnnotation.whisperId {
                    tapData["whisperId"] = whisperId
                }
                
                notifyListeners("onMarkerTap", data: tapData)
                
                return
            }
        }
    }
    
    /**
     * Re-cluster whispers after zoom change.
     * Called after zoom animation completes.
     */
    private func reclusterWhispers() {
        guard let mapView = self.mapView else { return }
        
        // Collect all individual whispers (extract from clusters + individual annotations)
        var allWhispers: [CustomPointAnnotation] = []
        
        for annotation in mapView.annotations {
            if let cluster = annotation as? WhisperClusterAnnotation {
                allWhispers.append(contentsOf: cluster.whisperAnnotations)
            } else if let whisper = annotation as? CustomPointAnnotation {
                allWhispers.append(whisper)
            }
        }
        
        // Restore original coordinates before re-clustering
        // This ensures whispers always cluster based on their TRUE geographic position
        for whisper in allWhispers {
            if let originalCoord = whisper.originalCoordinate {
                whisper.coordinate = originalCoord
            }
        }
        
        // Remove old annotations (but keep user location and mock location)
        mapView.removeAnnotations(mapView.annotations.filter { annotation in
            // Keep MKUserLocation (native GPS dot)
            if annotation is MKUserLocation { return false }
            
            // Keep mock location annotation (for TikTok demo)
            if let pointAnnotation = annotation as? MKPointAnnotation,
               pointAnnotation.title == "MockUserLocation" {
                return false
            }
            
            // Remove everything else (whispers, clusters)
            return true
        })
        
        // Re-cluster with current zoom level (using restored original coordinates)
        let clustered = self.clusterNearbyWhispers(allWhispers)
        mapView.addAnnotations(clustered)
        
    }
    
    /**
     * Cluster nearby whispers based on geographic proximity.
     * IDENTICAL LOGIC to MapComponent: whispers within clusteringThreshold meters are grouped.
     * 
     * CRITICAL FIXES:
     * - Only create cluster if count >= 2 (avoid "+1 more" bug)
     * - Prioritize whisper with profile photo as main whisper
     * - Use stable coordinate (centroid of all whispers, not just first)
     * 
     * Returns array of MKAnnotation (mix of individual CustomPointAnnotation and WhisperClusterAnnotation).
     */
    private func clusterNearbyWhispers(_ annotations: [CustomPointAnnotation]) -> [MKAnnotation] {
        guard let mapView = self.mapView else { return annotations }
        
        var result: [MKAnnotation] = []
        var processed: Set<String> = []
        
        // Get current map zoom level (approximate - based on visible region span)
        let zoomLevel = self.getApproximateZoomLevel()
        
        // DYNAMIC CLUSTERING THRESHOLD based on zoom (exponential scale like Google Maps)
        let dynamicThreshold: Double
        if zoomLevel < 5 {
            dynamicThreshold = 500000  // World - 500km (clusters continents)
        } else if zoomLevel < 8 {
            dynamicThreshold = 200000  // Continent - 200km (clusters far cities like Varese-Verona)
        } else if zoomLevel < 10 {
            dynamicThreshold = 50000   // Country - 50km (clusters provinces)
        } else if zoomLevel < 12 {
            dynamicThreshold = 10000   // City - 10km (clusters neighborhoods)
        } else if zoomLevel < 14 {
            dynamicThreshold = 2000    // District - 2km (clusters blocks)
        } else if zoomLevel < 16 {
            dynamicThreshold = 500     // Street - 500m (clusters nearby streets)
        } else if zoomLevel < 18 {
            dynamicThreshold = 200     // Building - 200m (clusters same area)
        } else {
            dynamicThreshold = 50      // Very close - 50m (individual whispers)
        }
        
        // Disable clustering at VERY high zoom levels (> 18 = single building)
        // BUT still apply spreading to overlapping whispers
        if zoomLevel > 18 {
            return applySpreadingToOverlappingWhispers(annotations)
        }
        
        for annotation in annotations {
            guard let whisperId = annotation.whisperId else {
                result.append(annotation)
                continue
            }
            
            if processed.contains(whisperId) {
                continue
            }
            
            // Find all nearby whispers within threshold
            let nearby = annotations.filter { otherAnnotation in
                guard let otherWhisperId = otherAnnotation.whisperId,
                      !processed.contains(otherWhisperId) else {
                    return false
                }
                
                // Use ORIGINAL coordinates for distance calculation
                // This ensures clustering is based on TRUE geographic proximity, not modified positions
                let coord1 = annotation.originalCoordinate ?? annotation.coordinate
                let coord2 = otherAnnotation.originalCoordinate ?? otherAnnotation.coordinate
                
                let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
                let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
                let distance = location1.distance(from: location2)
                
                return distance <= dynamicThreshold
            }
            
            // Only cluster if 2+ whispers (avoid "+1 more" bug)
            if nearby.count >= 2 {
                // PRIORITIZE clickable whispers as main whisper (inside radius)
                // Then prioritize whisper with profile photo
                let mainWhisper = nearby.first { $0.isClickable } 
                    ?? nearby.first { $0.iconUrl != nil && !$0.iconUrl!.isEmpty } 
                    ?? nearby.first!

                // Calculate centroid using ORIGINAL coordinates (true geographic position)
                let avgLat = nearby.map { ($0.originalCoordinate ?? $0.coordinate).latitude }.reduce(0, +) / Double(nearby.count)
                let avgLon = nearby.map { ($0.originalCoordinate ?? $0.coordinate).longitude }.reduce(0, +) / Double(nearby.count)
                
                let cluster = WhisperClusterAnnotation()
                cluster.whisperAnnotations = nearby
                cluster.mainWhisper = mainWhisper
                cluster.coordinate = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
                cluster.title = mainWhisper.title
                cluster.moreText = self.moreWhispersTranslation
                
                result.append(cluster)
                
                // Mark all as processed
                for whisper in nearby {
                    if let id = whisper.whisperId {
                        processed.insert(id)
                    }
                }
            } else {
                // Individual whisper (solo or not clustered)
                result.append(annotation)
                processed.insert(whisperId)
            }
        }
        
        // Save current zoom level for next comparison
        self.lastClusteredZoomLevel = zoomLevel
        
        return result
    }
    
    /**
     * Get approximate zoom level from current map region.
     * Web zoom 14 ≈ 0.05 degrees span.
     */
    private func getApproximateZoomLevel() -> Double {
        guard let mapView = self.mapView else { return 14.0 }
        
        let span = mapView.region.span.latitudeDelta
        let baseSpan = 0.05
        let zoomFactor = span / baseSpan
        let zoom = 14.0 - log2(zoomFactor)
        
        return zoom
    }
    
    /**
     * Apply spreading to overlapping whispers without clustering.
     * Used at very high zoom levels (> 18) where clustering is disabled.
     * Finds groups of overlapping whispers (< 5m apart) and spreads them in a circle.
     */
    private func applySpreadingToOverlappingWhispers(_ annotations: [CustomPointAnnotation]) -> [MKAnnotation] {
        var processed: Set<String> = []
        var result: [MKAnnotation] = []
        
        let threshold: CLLocationDistance = 5.0
        
        for annotation in annotations {
            guard let whisperId = annotation.whisperId else {
                result.append(annotation)
                continue
            }
            
            if processed.contains(whisperId) {
                continue
            }
            
            let nearby = annotations.filter { otherAnnotation in
                guard let otherWhisperId = otherAnnotation.whisperId,
                      !processed.contains(otherWhisperId) else {
                    return false
                }
                
                let coord1 = annotation.originalCoordinate ?? annotation.coordinate
                let coord2 = otherAnnotation.originalCoordinate ?? otherAnnotation.coordinate
                
                let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
                let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
                let distance = location1.distance(from: location2)
                
                return distance <= threshold
            }
            
            if nearby.count >= 2 {
                let centerLat = nearby.map { ($0.originalCoordinate ?? $0.coordinate).latitude }.reduce(0, +) / Double(nearby.count)
                let centerLon = nearby.map { ($0.originalCoordinate ?? $0.coordinate).longitude }.reduce(0, +) / Double(nearby.count)
                let centerCoord = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                
                let baseRadius: Double = 3.0
                let perWhisperOffset: Double = 0.5
                let spreadRadius = baseRadius + (perWhisperOffset * Double(nearby.count))
                
                let angleStep = 2.0 * .pi / Double(nearby.count)
                
                for (index, whisper) in nearby.enumerated() {
                    let angle = Double(index) * angleStep
                    
                    let deltaLat = (spreadRadius * sin(angle)) / 111000.0
                    let deltaLon = (spreadRadius * cos(angle)) / (111000.0 * cos(centerCoord.latitude * .pi / 180.0))
                    
                    let newCoord = CLLocationCoordinate2D(
                        latitude: centerCoord.latitude + deltaLat,
                        longitude: centerCoord.longitude + deltaLon
                    )
                    whisper.coordinate = newCoord
                    whisper.originalCoordinate = newCoord
                    
                    result.append(whisper)
                    if let id = whisper.whisperId {
                        processed.insert(id)
                    }
                }
            } else {
                result.append(annotation)
                processed.insert(whisperId)
            }
        }
        
        return result
    }
    
    // AUTO-SYNC: Handle location updates when map is already initialized
    private func handleLocationUpdate(_ location: CLLocation) {
        DispatchQueue.main.async {
            guard let mapView = self.mapView else { return }
            
            let coordinate = location.coordinate
            
            // AUTO-SYNC: Update circle position if enabled
            if self.autoSyncEnabled, let currentRadius = self.currentUserRadius {
                // Remove existing circle
                if let existingCircle = self.userCircle {
                    mapView.removeOverlay(existingCircle)
                }
                
                // Create new circle at current location with same radius
                let newCircle = MKCircle(center: coordinate, radius: currentRadius)
                self.userCircle = newCircle
                mapView.addOverlay(newCircle)
                
            }
            
            // Notify Angular with the new location (existing functionality)
            self.notifyListeners("locationUpdate", data: [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ])
        }
    }
}
