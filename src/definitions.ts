export interface appleMapsSdkPlugin {
  echo(options: { value: string }): Promise<{ value: string }>;
  initAppleMaps(): Promise<{ status: string }>;  // Initialization
  showAppleMaps(): Promise<{ status: string }>;  // No parameters anymore
  hideAppleMaps(): Promise<{ status: string }>;  // Make the map invisible
  setValuesAppleMaps(options: { dataPoints: { latitude: number; longitude: number; label: string }[] }): Promise<{ status: string }>;
  setCenterPoint(options: { latitude: number; longitude: number }): Promise<{ status: string }>;
  enableArchiveMode(): Promise<{ status: string }>;  // Enable archive mode (hide circle, no expiry borders)
  disableArchiveMode(): Promise<{ status: string }>;  // Disable archive mode (restore normal)
  closeAppleMaps(): Promise<{ status: string }>;  // Close the map
  isAppleMapsVisible(): Promise<{ status: number }>;  // Return value: 0 = not initialized, 1 = invisible, 2 = visible
  captureMapSnapshot(options: {
    latitude: number;
    longitude: number;
    width?: number;
    height?: number;
    spanMeters?: number;
  }): Promise<{ imageBase64: string; width: number; height: number }>;

  /**
   * v2.1: Apre Instagram Stories Editor con un'immagine come background.
   * Internamente usa UIPasteboard (richiesta IG) — l'URL scheme non supporta il payload.
   * @param imageBase64 - PNG base64 (con o senza prefisso data URI)
   * @param sourceApplication - bundle ID o FB App ID (default: bundle ID)
   */
  shareImageToInstagramStory(options: {
    imageBase64: string;
    sourceApplication?: string;
  }): Promise<{ status: string }>;
}