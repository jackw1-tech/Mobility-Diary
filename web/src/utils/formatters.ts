export function displayName(firstName: string, lastName: string, fallback: string): string {
  const fullName = [firstName, lastName].filter(Boolean).join(' ').trim();
  return fullName || fallback;
}

export function formatDateTime(value: string | null, fallback = 'Nessun viaggio'): string {
  if (!value) return fallback;
  return new Intl.DateTimeFormat('it-IT', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(value));
}

export function formatDateTimeInput(value?: string | null): string {
  if (!value) return '';
  const date = new Date(value);
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
}

export function formatDistance(meters: number | null | undefined): string {
  if (meters == null) return 'N/D';
  if (meters >= 1000) return `${(meters / 1000).toFixed(1)} km`;
  return `${Math.round(meters)} m`;
}

export function formatDuration(totalSeconds: number): string {
  const minutes = Math.max(0, Math.round(totalSeconds / 60));
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  if (hours === 0) return `${remainingMinutes} min`;
  return remainingMinutes === 0
    ? `${hours} h`
    : `${hours} h ${remainingMinutes} min`;
}

export function formatDurationPrecise(totalSeconds: number): string {
  if (totalSeconds < 60) {
    return `${totalSeconds.toFixed(totalSeconds < 10 ? 2 : 1)} s`;
  }
  const totalMinutes = Math.floor(totalSeconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const seconds = Math.round(totalSeconds % 60);
  if (hours === 0) {
    return seconds === 0 ? `${minutes} min` : `${minutes} min ${seconds} s`;
  }
  return minutes === 0 ? `${hours} h` : `${hours} h ${minutes} min`;
}

export function formatTripStatus(status: string): string {
  const labels: Record<string, string> = {
    OPEN: 'Aperto',
    CLOSED: 'Chiuso',
    PROCESSED: 'Processato',
  };
  return labels[status] ?? status;
}
