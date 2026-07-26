# SalesSetu Module 036 — Production Baseline Bundle

This bundle preserves the runtime changes and verification scripts that were
applied after `036_Platform_Integration_Validation_Engine.sql`.

## Repository placement

Extract into the repository root so the files land in:

- `supabase/patches/`
- `supabase/tests/`

## Applied production patch order

1. `036_patch_run_platform_validation_v3.sql`
2. `036_patch_tenant_organization_indexes_v2.sql`
3. `036_fk_index_batch_remediation.sql`
4. `036_run_production_metadata_validation.sql`
5. `036_batched_fk_orphan_integrity_audit.sql`
6. `036_post_install_schema_reload.sql`

## Verified production outcomes

- Quick validation: 2,102 / 2,102 passed
- Production metadata validation: 4,632 / 4,632 passed
- FK orphan integrity audit: 2,530 / 2,530 passed
- Smoke tests: 13 / 13 passed
- Tenant organization indexes: 622 / 622
- Missing FK index constraints after remediation: 0

## Important

The existing migration file remains the historical migration installed in the
database. The files in `supabase/patches/` are required to reproduce the exact
current production state. A future squashed migration can consolidate these
changes for clean-room deployments.
