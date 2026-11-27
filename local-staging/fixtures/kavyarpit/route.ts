import { NextRequest, NextResponse } from 'next/server';
import { TextDecoder } from 'node:util';
import { approvedIds } from '@/lib/project-discovery';
import { validateConsultation, type ConsultationInput } from '@/lib/consultation/contract';
import { submitConsultation } from '@/server/consultation-adapter';

const maxBytes = 8192;
const reply = (body: object, status: number) => NextResponse.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
export async function POST(request: NextRequest) {
  // Exact same-origin JSON requests only. Never use forwarded/posted tenant identity.
  const sameOrigin = `${request.nextUrl.protocol}//${request.headers.get('host') ?? ''}`;
  if (request.headers.get('origin') !== sameOrigin || request.headers.get('sec-fetch-site') === 'cross-site') return reply({ error: 'Invalid origin.' }, 403);
  if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return reply({ error: 'Use a JSON request.' }, 415);
  const declaredLength = Number(request.headers.get('content-length') ?? '0');
  if (!Number.isFinite(declaredLength) || declaredLength < 0 || declaredLength > maxBytes) return reply({ error: 'Request is too large.' }, 413);
  const reader = request.body?.getReader();
  if (!reader) return reply({ error: 'Invalid request.' }, 400);
  let data: Record<string, unknown>;
  try {
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let text = '', bytes = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) { await reader.cancel(); return reply({ error: 'Request is too large.' }, 413); }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error();
    data = parsed;
  } catch { return reply({ error: 'Invalid request.' }, 400); }
  finally { reader.releaseLock(); }
  // Tenant/source identity is never accepted, even when it matches the server value.
  if (['route_key', 'organization_id', 'organisation_id', 'tenant_id', 'org_id', 'source', 'campaign_name'].some(key => Object.hasOwn(data, key))) return reply({ error: 'Unsupported request fields.' }, 400);
  if (typeof data.website !== 'string' || data.website !== '') return reply({ error: 'Unable to process this request.' }, 400);
  const errors = validateConsultation(data, approvedIds);
  if (Object.keys(errors).length) return reply({ error: 'Please check the highlighted fields.', errors }, 400);
  // Copy only the validated contract, never pass through extra browser fields.
  const input: ConsultationInput = {
    name: String(data.name), phone: String(data.phone), location: String(data.location),
    project: String(data.project), budget: String(data.budget), configuration: String(data.configuration),
    timeline: String(data.timeline), siteVisit: String(data.siteVisit), consent: true, website: '',
    ...Object.fromEntries(['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'landing_page'].filter(key => typeof data[key] === 'string').map(key => [key, data[key]])),
  };
  try {
    const result = await submitConsultation(input);
    if (result.status === 'accepted') return reply({ ok: true }, 200);
    if (result.status === 'disabled') return reply({ code: 'DELIVERY_DISABLED', error: 'Online consultation delivery is not active. Your request has not been sent or saved. Please call our advisory team.' }, 503);
  } catch { /* No personal data, payloads or upstream details in logs/responses. */ }
  return reply({ error: 'Your request could not be confirmed. Please retry or call our advisory team.' }, 502);
}
