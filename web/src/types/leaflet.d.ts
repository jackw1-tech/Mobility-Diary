declare module 'leaflet' {
  export type LatLngTuple = [number, number];

  export type PolylineOptions = {
    color?: string;
    dashArray?: string;
    opacity?: number;
    weight?: number;
  };

  export type Map = {
    fitBounds(bounds: unknown, options?: unknown): void;
    remove(): void;
    setView(center: LatLngTuple, zoom: number): void;
  };

  export type Polyline = {
    addTo(map: Map): Polyline;
    getBounds(): unknown;
  };

  const L: {
    map(element: HTMLElement, options?: unknown): Map;
    polyline(points: LatLngTuple[], options?: PolylineOptions): Polyline;
    tileLayer(url: string, options?: unknown): { addTo(map: Map): unknown };
  };

  export default L;
}
