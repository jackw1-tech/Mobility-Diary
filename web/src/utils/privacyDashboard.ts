export type PrivacyLevel = 'precise' | 'approximate' | 'aggregated';

export type PrivacyMetrics = {
  privacy_perturbation: {
    mean_meters: number;
    max_meters: number;
    sample_count: number;
  };
  quality_of_service: {
    relative_distance_error: number;
    private_distance_meters: number;
    privacy_aware_distance_meters: number;
  };
};

export type PrivacyLevelOption = {
  value: PrivacyLevel;
  label: string;
  cellLabel: string;
  protectedLevel: boolean;
};

export const privacyLevelOptions: PrivacyLevelOption[] = [
  { value: 'precise', label: 'Precisa', cellLabel: 'Nessun cloaking', protectedLevel: false },
  { value: 'approximate', label: 'Approssimata', cellLabel: 'Celle 150 m', protectedLevel: true },
  { value: 'aggregated', label: 'Aggregata', cellLabel: 'Celle 400 m', protectedLevel: true },
];

export function privacyLevelLabel(level: PrivacyLevel): string {
  return privacyLevelOptions.find((option) => option.value === level)?.label ?? level;
}

export function privacyLevelCellLabel(level: PrivacyLevel): string {
  return privacyLevelOptions.find((option) => option.value === level)?.cellLabel ?? '';
}

export function isProtectedLevel(level: PrivacyLevel): boolean {
  return level !== 'precise';
}

// Mirrors formatDistance in ./formatters; kept inline so this module stays
// dependency-free and runnable under the extensionless node --test pipeline.
export function formatMeters(meters: number): string {
  if (meters >= 1000) return `${(meters / 1000).toFixed(1)} km`;
  return `${Math.round(meters)} m`;
}

export type PrivacyMetricCard = {
  key: string;
  label: string;
  value: string;
  hint: string;
};

export function privacyMetricCards(
  metrics: PrivacyMetrics,
  level: PrivacyLevel,
): PrivacyMetricCard[] {
  const { privacy_perturbation: perturbation, quality_of_service: quality } = metrics;
  return [
    {
      key: 'perturbation-mean',
      label: 'Perturbazione media',
      value: formatMeters(perturbation.mean_meters),
      hint: `${perturbation.sample_count} punti`,
    },
    {
      key: 'perturbation-max',
      label: 'Perturbazione massima',
      value: formatMeters(perturbation.max_meters),
      hint: privacyLevelCellLabel(level),
    },
    {
      key: 'quality-loss',
      label: 'Perdita di qualità',
      value: `${(quality.relative_distance_error * 100).toFixed(1)}%`,
      hint: `${formatMeters(quality.privacy_aware_distance_meters)} vs ${formatMeters(quality.private_distance_meters)}`,
    },
  ];
}
