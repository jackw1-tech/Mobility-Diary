declare module 'leaflet' {
  export type LatLngTuple = [number, number];

  export type LatLng = {
    lat: number;
    lng: number;
  };

  export type Point = {
    x: number;
    y: number;
  };

  export type PolylineOptions = {
    color?: string;
    dashArray?: string;
    opacity?: number;
    weight?: number;
  };

  export type CircleMarkerOptions = {
    color?: string;
    fillColor?: string;
    fillOpacity?: number;
    radius?: number;
    weight?: number;
  };

  export type RectangleOptions = PolylineOptions & {
    fillColor?: string;
    fillOpacity?: number;
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

  export type CircleMarker = {
    addTo(map: Map): CircleMarker;
    bindTooltip(content: string): CircleMarker;
  };

  export type Rectangle = {
    addTo(map: Map): Rectangle;
    bindTooltip(content: string): Rectangle;
  };

  const L: {
    CRS: {
      EPSG3857: {
        project(position: LatLng): Point;
        unproject(point: Point): LatLng;
      };
    };
    map(element: HTMLElement, options?: unknown): Map;
    latLng(lat: number, lng: number): LatLng;
    latLngBounds(southWest: LatLng, northEast: LatLng): unknown;
    point(x: number, y: number): Point;
    polyline(points: LatLngTuple[], options?: PolylineOptions): Polyline;
    rectangle(bounds: unknown, options?: RectangleOptions): Rectangle;
    circleMarker(center: LatLngTuple, options?: CircleMarkerOptions): CircleMarker;
    tileLayer(url: string, options?: unknown): { addTo(map: Map): unknown };
  };

  export default L;
}
