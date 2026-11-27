/** Public consultation contract. No tenant identifiers or delivery configuration. */
export const consultationOptions = {
  location: ['Noida', 'Greater Noida', 'Greater Noida West', 'Wave City', 'Siddharth Vihar', 'Help me decide'],
  budget: ['₹1.5–1.75 Cr', '₹1.75–2 Cr', '₹2–2.5 Cr', '₹2.5 Cr+', 'Help me decide'],
  configuration: ['3 BHK', '4 BHK', 'Help me decide'],
  timeline: ['Within 1 month', '1–3 months', '3–6 months', 'Exploring options'],
  siteVisit: ['Yes', 'Not yet'],
} as const;
export const utmKeys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'] as const;
export type Attribution = Partial<Record<typeof utmKeys[number], string>> & { landing_page?: string };
export type ConsultationInput = {
  name: string; phone: string; location: string; project: string; budget: string;
  configuration: string; timeline: string; siteVisit: string; consent: boolean; website: string;
} & Attribution;
export type ConsultationErrors = Partial<Record<keyof ConsultationInput, string>>;
export function validateConsultation(data: Record<string, unknown>, projectIds: readonly string[]): ConsultationErrors {
  const errors: ConsultationErrors = {};
  if (typeof data.name !== 'string' || data.name.trim().length < 2 || data.name.trim().length > 100 || /[\u0000-\u001f\u007f]/.test(data.name)) errors.name = 'Enter your full name (2–100 characters).';
  if (typeof data.phone !== 'string' || !/^(?:\+91[ -]?)?[6-9]\d{9}$/.test(data.phone.trim())) errors.phone = 'Enter a valid 10-digit Indian mobile number, optionally prefixed with +91.';
  for (const key of Object.keys(consultationOptions) as (keyof typeof consultationOptions)[]) {
    if (!(consultationOptions[key] as readonly unknown[]).includes(data[key])) errors[key] = 'Choose an option from the list.';
  }
  if (typeof data.project !== 'string' || ![...projectIds, 'undecided'].includes(data.project)) errors.project = 'Choose an approved project or Help me decide.';
  if (data.consent !== true) errors.consent = 'Please give contact consent to continue.';
  return errors;
}
/** Only explicitly approved marketing parameters and public main-site paths survive. */
export function sanitizeAttribution(data: Record<string, unknown>): Attribution {
  const attribution: Attribution = {};
  for (const key of utmKeys) {
    const value = data[key];
    if (typeof value === 'string' && value.length <= 200 && !/[\u0000-\u001f\u007f]/.test(value)) attribution[key] = value;
  }
  if (typeof data.landing_page === 'string' && data.landing_page.length <= 2048) {
    try {
      const url = new URL(data.landing_page);
      if (url.protocol === 'https:' && ['kavyarpitrealty.com', 'www.kavyarpitrealty.com'].includes(url.hostname) && !url.port && !url.username && !url.password && /^\/(?:projects(?:\/(?:calisto|imperia|divine|atlantis))?|consultation)?\/?$/.test(url.pathname)) {
        // Query strings can contain personal data. Keep only the approved UTM fields.
        const clean = new URL(url.pathname, 'https://kavyarpitrealty.com');
        for (const key of utmKeys) { const value = url.searchParams.get(key); if (value && value.length <= 200 && !/[\u0000-\u001f\u007f]/.test(value)) clean.searchParams.set(key, value); }
        attribution.landing_page = clean.toString();
      }
    } catch { /* Missing/invalid attribution never changes routing or validation. */ }
  }
  return attribution;
}
