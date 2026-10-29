export const GEO_TAGS = [
  "noida",
  "greater_noida",
  "greater_noida_west",
  "siddharth_vihar",
  "wave_city",
  "raj_nagar_extension",
  "ghaziabad",
] as const;

export type GeoTag = (typeof GEO_TAGS)[number];

export const GEO_TAG_LABELS: Record<GeoTag, string> = {
  noida: "Noida",
  greater_noida: "Greater Noida",
  greater_noida_west: "Greater Noida West",
  siddharth_vihar: "Siddharth Vihar",
  wave_city: "Wave City",
  raj_nagar_extension: "Raj Nagar Extension",
  ghaziabad: "Ghaziabad",
};

export function isGeoTag(value: string): value is GeoTag {
  return GEO_TAGS.includes(value as GeoTag);
}

export function geoTagLabel(value: string | null | undefined): string | null {
  return value && isGeoTag(value) ? GEO_TAG_LABELS[value] : null;
}

/**
 * Read-only fallback for older leads. New and edited leads persist the selected
 * canonical tag, so future assignment rules never depend on fuzzy matching.
 */
export function deriveGeoTag(location: string | null | undefined, city: string | null | undefined): GeoTag | null {
  const source = `${location ?? ""} ${city ?? ""}`.toLocaleLowerCase();
  if (/greater\s*noida\s*(west|w)|noida\s*extension/.test(source)) return "greater_noida_west";
  if (/siddharth\s*vihar/.test(source)) return "siddharth_vihar";
  if (/wave\s*city/.test(source)) return "wave_city";
  if (/raj\s*nagar\s*extension/.test(source)) return "raj_nagar_extension";
  if (/greater\s*noida/.test(source)) return "greater_noida";
  if (/noida/.test(source)) return "noida";
  if (/ghaziabad/.test(source)) return "ghaziabad";
  return null;
}
