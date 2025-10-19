# capacitor-plugin-appleMaps

A high-performance Capacitor plugin that provides native iOS Apple Maps integration with advanced marker customization, smooth animations, and haptic feedback.

## Features

- **Native Performance**: Direct MapKit integration for smooth rendering and instant interactions
- **Custom Markers**: Support for profile photos, initials with colored backgrounds, and dynamic border colors
- **Haptic Feedback**: Premium iOS-style haptic feedback on marker interactions
- **Circle Overlays**: Visualize radius or zones with customizable stroke and fill colors
- **Flexible Positioning**: Configure map position with custom offsets for headers/footers
- **Event Bridge**: Real-time marker tap events with custom data payload
- **Efficient Rendering**: Batch marker updates with no flickering or visual artifacts

Perfect for location-based apps, social networks, delivery services, or any app requiring high-quality native maps on iOS.apple-maps-sdk

The apple-maps-sdk is a Capacitor plugin that provides access to the native iOS Apple Maps SDK for developers to integrate Apple Maps into their mobile applications. This plugin allows users to utilize the native Apple Maps API to display maps, set markers, and adjust the map’s center point directly within their app. Features such as showing and hiding the map, adding custom data points, and checking if the map is visible are included. It also supports managing the current location and other map settings using native iOS functionality. This plugin is perfect for developers who want to leverage the full capabilities of Apple’s native map features on iOS devices.

## Install

```bash
npm install @yassinechar/capacitor-plugin-applemaps
npx cap sync
```

## Usage Example

```typescript
import { appleMapsSdk } from '@yassinechar/capacitor-plugin-applemaps';

// Initialize map
await appleMapsSdk.initAppleMaps({ 
  topOffset: 60,      // Space for header
  heightOffset: 100   // Space for footer
});

// Show map
await appleMapsSdk.showAppleMaps();

// Add custom markers with photos and colored borders
await appleMapsSdk.setValuesAppleMaps({
  dataPoints: [
    {
      latitude: 37.7749,
      longitude: -122.4194,
      label: "San Francisco",
      iconUrl: "https://example.com/photo.jpg",
      initials: "SF",
      avatarColor: "#F25450",
      expiryColor: "green",  // red, yellow, or green border
      markerSize: 60,
      whisperId: "marker-123",
      isClickable: true
    }
  ]
});

// Add radius circle
await appleMapsSdk.addCircle({
  latitude: 37.7749,
  longitude: -122.4194,
  radius: 500,  // meters
  strokeColor: "#00E5FF",
  fillColor: "#00E5FF4D",
  strokeWidth: 2
});

// Listen for marker taps
appleMapsSdk.addListener('onMarkerTap', (data) => {
  console.log('Marker tapped:', data.whisperId, data.isClickable);
  // Navigate or show details
});
```

## Advanced Features

### Custom Marker Avatars
- **Profile Photos**: Load async from URL with automatic caching
- **Initials Fallback**: Text-based avatars with colored backgrounds (12-color palette)
- **Generic Fallback**: Default user icon if no data provided
- **Border Colors**: Visual status indication (red/yellow/green)

### Performance Optimizations
- **Instant Haptic Feedback**: iOS-native haptic on tap for premium feel
- **Batch Rendering**: Update multiple markers without flickering
- **Efficient Image Loading**: Async URLSession with main thread updates
- **No Animation Delays**: Direct annotation manipulation for instant interactions

### Map Positioning
- **Flexible Layout**: Configure top/bottom offsets for custom UI
- **Transparent WebView**: Map renders below Capacitor webview
- **Safe Area Support**: Automatic safe area insets handling

## API

<docgen-index>

* [`echo(...)`](#echo)
* [`initAppleMaps()`](#initapplemaps)
* [`showAppleMaps()`](#showapplemaps)
* [`hideAppleMaps()`](#hideapplemaps)
* [`setValuesAppleMaps(...)`](#setvaluesapplemaps)
* [`setCenterPoint(...)`](#setcenterpoint)
* [`closeAppleMaps()`](#closeapplemaps)
* [`isAppleMapsVisible()`](#isapplemapsvisible)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### echo(...)

```typescript
echo(options: { value: string; }) => Promise<{ value: string; }>
```

| Param         | Type                            |
| ------------- | ------------------------------- |
| **`options`** | <code>{ value: string; }</code> |

**Returns:** <code>Promise&lt;{ value: string; }&gt;</code>

--------------------


### initAppleMaps()

```typescript
initAppleMaps() => Promise<{ status: string; }>
```

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### showAppleMaps()

```typescript
showAppleMaps() => Promise<{ status: string; }>
```

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### hideAppleMaps()

```typescript
hideAppleMaps() => Promise<{ status: string; }>
```

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### setValuesAppleMaps(...)

```typescript
setValuesAppleMaps(options: { dataPoints: { latitude: number; longitude: number; label: string; }[]; }) => Promise<{ status: string; }>
```

| Param         | Type                                                                                    |
| ------------- | --------------------------------------------------------------------------------------- |
| **`options`** | <code>{ dataPoints: { latitude: number; longitude: number; label: string; }[]; }</code> |

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### setCenterPoint(...)

```typescript
setCenterPoint(options: { latitude: number; longitude: number; }) => Promise<{ status: string; }>
```

| Param         | Type                                                  |
| ------------- | ----------------------------------------------------- |
| **`options`** | <code>{ latitude: number; longitude: number; }</code> |

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### closeAppleMaps()

```typescript
closeAppleMaps() => Promise<{ status: string; }>
```

**Returns:** <code>Promise&lt;{ status: string; }&gt;</code>

--------------------


### isAppleMapsVisible()

```typescript
isAppleMapsVisible() => Promise<{ status: number; }>
```

**Returns:** <code>Promise&lt;{ status: number; }&gt;</code>

--------------------

</docgen-api>
