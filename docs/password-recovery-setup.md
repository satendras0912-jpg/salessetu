# Password recovery rollout

Deploy the recovery route before changing the hosted Supabase Reset password email template. No SQL migration is needed. Existing PKCE callback links remain supported, but expired or already used tokens cannot be repaired.

## Hosted settings (manual verification required)

1. Verify the canonical production domain actually serving the app. Set Supabase Authentication > URL Configuration > Site URL and Vercel Production `NEXT_PUBLIC_APP_URL` to the same origin (currently intended: `https://www.salessetu.in`). Avoid switching between apex and www during recovery.
2. Retain the existing allowed callback `https://www.salessetu.in/auth/callback?next=/update-password` and any deliberately supported exact origins. Do not add broad wildcard production redirects.
3. In Authentication > Email Templates > Reset password, use the following link. This intentionally uses SiteURL so preview requests also recover through the production host; do not use an arbitrary user-provided redirect destination.

```html
<h2>Reset your SalesSetu password</h2>
<p>Follow this link, then select Continue to choose a new password.</p>
<p><a href="{{ .SiteURL }}/auth/recovery?token_hash={{ .TokenHash }}">Reset password</a></p>
<p>If you did not request this change, ignore this email.</p>
```

The GET displays a confirmation form; only its explicit server-action POST calls verifyOtp with type recovery. This reduces accidental consumption by link scanners that only fetch the page and removes the request-browser PKCE verifier requirement for this new template. It cannot protect against scanners submitting forms, nor restore a consumed token.

## Verification

- Request one fresh email after deployment AND template update. Open the newest message, including from a different browser profile, confirm, choose a password, and verify login. Do not share the reset URL or password.
- Reusing that email must show the invalid/expired reset page, never silently open marketing content.
- Verify both query-string and fragment-only `error_code=otp_expired` homepage redirects display the recovery error screen. Normal homepage visits remain unchanged.
- Existing PKCE links still require the browser that requested them. Legacy implicit recovery fragments are rejected with guidance to request a new supported link.
- Do not log token hashes, passwords, access tokens or full auth URLs. Treat URL query strings in hosting/request logs as sensitive.

Official references: https://supabase.com/docs/guides/auth/auth-email-templates and https://supabase.com/docs/guides/auth/passwords
