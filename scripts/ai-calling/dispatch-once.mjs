import { pathToFileURL } from 'node:url';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function dispatchOnce(env, fetcher = fetch, now = new Date()) {
  if (env.AI_CALL_AUTO_DISPATCH_ENABLED !== 'true') return { status: 'disabled' };
  const org = env.AI_CALL_DISPATCH_ORGANIZATION_ID?.trim();
  const secret = env.AI_CALL_DISPATCH_SECRET?.trim();
  if (!UUID.test(org ?? '')) throw new Error('A single organization UUID is required.');
  if (!secret || secret.length < 32 || /\s/.test(secret)) throw new Error('Dispatch secret is missing or malformed.');
  const start = Number(env.AI_CALL_WINDOW_START_HOUR);
  const end = Number(env.AI_CALL_WINDOW_END_HOUR);
  if (!env.AI_CALL_WINDOW_START_HOUR || !env.AI_CALL_WINDOW_END_HOUR ||
      !Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end > 24 || start >= end) {
    throw new Error('Explicit calling hours are required (0 <= start < end <= 24).');
  }
  const timezone = env.AI_CALL_TIMEZONE?.trim();
  if (!timezone) throw new Error('Calling timezone is required.');
  const hour = Number(new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone, hour: '2-digit', hourCycle: 'h23',
  }).format(now));
  if (hour < start || hour >= end) return { status: 'outside_calling_window' };

  // Use the canonical host directly: never redirect a secret-bearing request.
  const url = 'https://www.salessetu.in/api/ai-calling/dispatch';
  let response;
  let payload;
  try {
    response = await fetcher(url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(75_000),
      headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json' },
      body: JSON.stringify({ organizationId: org, workerId: `scheduler-${env.GITHUB_RUN_ID ?? 'local'}`, lockMinutes: 10 }),
    });
    if (![200, 202].includes(response.status)) throw new Error('HTTP failure');
    payload = await response.json();
  } catch {
    // Do not print response bodies, tokens, provider details or contact data.
    throw new Error('Dispatch outcome is uncertain or rejected. Pause scheduling and inspect server/job logs before retrying.');
  }
  const status = payload?.result?.status;
  if (payload?.ok !== true || !['empty', 'initiated'].includes(status) ||
      (status === 'empty' && response.status !== 200) ||
      (status === 'initiated' && response.status !== 202)) {
    throw new Error('Unexpected dispatch response. Inspect job state before retrying.');
  }
  return { status };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    console.log(JSON.stringify(await dispatchOnce(process.env)));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
