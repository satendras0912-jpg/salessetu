import 'server-only';
import { createHmac } from 'node:crypto';
import { sanitizeAttribution, type ConsultationInput } from '@/lib/consultation/contract';

const CAPTURE_ROUTE = 'kavyarpit-web';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const submissionUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const nilUuid = '00000000-0000-0000-0000-000000000000';

/**
 * Server-only mapping to the verified SalesSetu lead_capture_intake schema.
 * The browser never chooses organization_id, capture route, source, or campaign.
 * This function prepares data only: it does not contact a webhook.
 */
export function buildConsultationPayload(input: ConsultationInput) {
  const { landing_page, ...utm } = sanitizeAttribution(input);
  return {
    route_key: CAPTURE_ROUTE,
    full_name: input.name.trim(),
    phone: '+91' + input.phone.replace(/\D/g, '').slice(-10),
    preferred_project: input.project,
    preferred_location: input.location,
    source: 'kavyarpit_buyer_consultation',
    campaign_name: 'Kavyarpit Buyer Consultation',
    ...utm,
    ...(landing_page ? { landing_page_url: landing_page } : {}),
    metadata: {
      consent: true,
      budget: input.budget,
      configuration: input.configuration,
      purchase_timeline: input.timeline,
      site_visit_interest: input.siteVisit,
    },
  };
}

/**
 * Proposed idempotency contract for the future verified webhook integration.
 * A per-form UUIDv4 is stable across retries; the HMAC binds it to this route
 * and the normalized phone, without exposing the phone or signing secret.
 * Only a trusted server may supply the secret. No browser-supplied key is trusted.
 */
export function buildIdempotentConsultationPayload(
  input: ConsultationInput,
  submissionId: string,
  dedupeSecret: string,
) {
  if (!submissionUuid.test(submissionId)) throw new Error('Invalid submission identifier');
  if (typeof dedupeSecret !== 'string' || dedupeSecret.length < 32) throw new Error('Idempotency configuration missing');
  const payload = buildConsultationPayload(input);
  if (!/^\+91[6-9]\d{9}$/.test(payload.phone)) throw new Error('Invalid mobile number');
  const idempotency_key = createHmac('sha256', dedupeSecret)
    .update(['consultation-v1', payload.route_key, payload.phone, submissionId.toLowerCase()].join(':'))
    .digest('hex');
  return { ...payload, idempotency_key };
}

/**
 * Database ingest RPC returns intake_id, status, lead_id and duplicate.
 * Treat 2xx, queue receipt, duplicate-only notice and a null/missing lead_id
 * as *unconfirmed*. A trusted webhook must pass through a post-commit RPC
 * receipt; the receipt shape alone does not prove provenance or tenant routing.
 */
export function isConfirmedSavedLeadReceipt(httpStatus: number, value: unknown): boolean {
  if (!Number.isInteger(httpStatus) || httpStatus < 200 || httpStatus >= 300) return false;
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const receipt = value as Record<string, unknown>;
  const validId = (id: unknown) => typeof id === 'string' && uuid.test(id) && id.toLowerCase() !== nilUuid;
  if (receipt.status !== 'processed' || !validId(receipt.intake_id) || !validId(receipt.lead_id)) return false;
  if (typeof receipt.duplicate !== 'boolean') return false;
  if (receipt.route_key !== undefined && receipt.route_key !== CAPTURE_ROUTE) return false;
  return true;
}

export type ConsultationDeliveryResult = { status: 'disabled' } | { status: 'accepted' } | { status: 'failed' };

/**
 * Production safety gate: NOT wired to a webhook, environment toggle, queue or
 * database. Only after an independently approved n8n authentication, receipt
 * and retry contract will a separate implementation allow real submissions.
 * No current environment variable can enable delivery.
 */
export async function submitConsultation(input: ConsultationInput): Promise<ConsultationDeliveryResult> {
  buildConsultationPayload(input);
  return { status: 'disabled' };
}
