-- ============================================================
-- SalesSetu Enterprise
-- Migration 018: Document Management Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   005_site_visits.sql
--   006_bookings.sql
--   007_customer_success.sql
--   008_inventory.sql
--   010_ai_calling_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--
-- Scope:
--   • Multi-tenant document repository
--   • Folder hierarchy and entity-linked documents
--   • Supabase Storage object metadata
--   • Version control and immutable file history
--   • Document categories, tags and custom metadata
--   • Access policies, shares and secure download tokens
--   • Upload sessions and multipart-upload readiness
--   • Checksum, virus-scan and file-integrity controls
--   • OCR, extraction and AI-processing jobs
--   • Digital-signature envelopes and signatories
--   • Expiry, review, approval and retention workflows
--   • Event outbox, notifications, analytics and audit integration
--   • RLS, permissions, grants, health checks and validation
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. RBAC PERMISSIONS
-- ============================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
select
  p.module,
  p.action,
  p.code,
  p.description
from (
  values
    ('document','view','document.view','View documents'),
    ('document','view_all','document.view_all','View all organization documents'),
    ('document','upload','document.upload','Upload documents'),
    ('document','update','document.update','Update document metadata'),
    ('document','delete','document.delete','Archive or delete documents'),
    ('document','download','document.download','Download documents'),
    ('document','share','document.share','Share documents'),
    ('document','manage_folders','document.manage_folders','Manage document folders'),
    ('document','manage_categories','document.manage_categories','Manage document categories'),
    ('document','manage_access','document.manage_access','Manage document access'),
    ('document','manage_retention','document.manage_retention','Manage document retention'),
    ('document','manage_signatures','document.manage_signatures','Manage digital signatures'),
    ('document','manage_processing','document.manage_processing','Manage OCR and processing'),
    ('document','approve','document.approve','Approve or reject documents'),
    ('document','view_sensitive','document.view_sensitive','View sensitive documents'),
    ('document','view_logs','document.view_logs','View document logs'),
    ('document','view_analytics','document.view_analytics','View document analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. DOCUMENT CATEGORIES
-- ============================================================

create table if not exists public.document_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  category_code text not null,
  category_name text not null,
  description text,

  entity_scope text[] not null default '{}',
  allowed_mime_types text[] not null default '{}',
  maximum_file_size_bytes bigint,

  requires_approval boolean not null default false,
  requires_expiry boolean not null default false,
  requires_signature boolean not null default false,
  requires_virus_scan boolean not null default true,
  requires_checksum boolean not null default true,

  default_retention_days integer,
  sensitivity_level text not null default 'internal'
    check (
      sensitivity_level in (
        'public',
        'internal',
        'confidential',
        'restricted',
        'highly_restricted'
      )
    ),

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  is_system_category boolean not null default false,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,category_code)
);

create unique index if not exists document_categories_system_unique_idx
  on public.document_categories (category_code)
  where organization_id is null;

insert into public.document_categories (
  organization_id,
  category_code,
  category_name,
  description,
  entity_scope,
  requires_approval,
  requires_expiry,
  requires_signature,
  sensitivity_level,
  is_system_category
)
values
  (null,'lead_document','Lead Document','Documents collected during lead qualification',array['lead'],false,false,false,'confidential',true),
  (null,'kyc','KYC Document','Identity and address-verification documents',array['lead','customer','booking'],true,true,false,'highly_restricted',true),
  (null,'booking_form','Booking Form','Booking application and booking forms',array['booking','customer'],true,false,true,'restricted',true),
  (null,'agreement','Agreement','Agreement and contractual documents',array['booking','customer','builder','project'],true,true,true,'restricted',true),
  (null,'payment_receipt','Payment Receipt','Payment and transaction receipts',array['booking','customer','payment'],false,false,false,'confidential',true),
  (null,'site_visit','Site Visit Attachment','Site visit photographs and attachments',array['site_visit','lead'],false,false,false,'internal',true),
  (null,'inventory','Inventory Document','Inventory plans and unit documents',array['inventory','project'],false,true,false,'internal',true),
  (null,'builder','Builder Document','Builder approvals, brochures and credentials',array['builder','project'],true,true,false,'confidential',true),
  (null,'project','Project Document','Project plans, brochures and approvals',array['project','inventory'],true,true,false,'internal',true),
  (null,'call_recording','AI Call Recording','AI calling audio recordings',array['lead','ai_call'],false,true,false,'restricted',true),
  (null,'call_transcript','AI Call Transcript','AI call transcript documents',array['lead','ai_call'],false,true,false,'restricted',true),
  (null,'communication_attachment','Communication Attachment','Files attached to communication messages',array['lead','communication'],false,true,false,'confidential',true),
  (null,'customer_document','Customer Document','Customer lifecycle documents',array['customer','booking'],true,true,false,'confidential',true),
  (null,'system_export','System Export','System-generated export files',array['system'],false,true,false,'restricted',true)
on conflict do nothing;

-- ============================================================
-- 3. STORAGE BUCKET CONFIGURATION
-- ============================================================

create table if not exists public.document_storage_buckets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  bucket_code text not null,
  bucket_name text not null,
  provider text not null default 'supabase_storage'
    check (provider in ('supabase_storage','s3','gcs','azure','local','custom')),

  external_bucket_id text not null,
  base_path text,

  is_public boolean not null default false,
  encryption_enabled boolean not null default true,
  versioning_enabled boolean not null default true,

  maximum_file_size_bytes bigint,
  allowed_mime_types text[] not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','error','archived')),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,bucket_code)
);

-- ============================================================
-- 4. FOLDERS
-- ============================================================

create table if not exists public.document_folders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  parent_folder_id uuid references public.document_folders(id) on delete cascade,

  folder_name text not null,
  folder_code text,
  full_path text,

  entity_type text,
  entity_id uuid,
  entity_reference text,

  visibility text not null default 'private'
    check (visibility in ('private','organization','team','public','restricted')),

  status text not null default 'active'
    check (status in ('active','archived','deleted')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,parent_folder_id,folder_name)
);

create index if not exists document_folders_entity_idx
  on public.document_folders (
    organization_id,
    entity_type,
    entity_id
  );

-- ============================================================
-- 5. DOCUMENTS
-- ============================================================

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  folder_id uuid references public.document_folders(id) on delete set null,
  category_id uuid references public.document_categories(id) on delete set null,
  storage_bucket_id uuid references public.document_storage_buckets(id) on delete set null,

  document_code text,
  document_name text not null,
  description text,

  document_type text,
  mime_type text,
  file_extension text,
  file_size_bytes bigint,

  storage_provider text not null default 'supabase_storage',
  storage_bucket text,
  storage_path text,
  storage_object_id text,
  external_url text,

  checksum_algorithm text default 'sha256',
  checksum_value text,

  current_version_number integer not null default 1,
  current_version_id uuid,

  entity_type text,
  entity_id uuid,
  entity_reference text,

  lead_id uuid references public.leads(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete cascade,
  site_visit_id uuid references public.site_visits(id) on delete cascade,

  visibility text not null default 'private'
    check (visibility in ('private','organization','team','public','restricted')),

  lifecycle_status text not null default 'draft'
    check (
      lifecycle_status in (
        'draft',
        'uploading',
        'processing',
        'pending_review',
        'approved',
        'rejected',
        'active',
        'expired',
        'archived',
        'deleted',
        'quarantined'
      )
    ),

  approval_status text not null default 'not_required'
    check (
      approval_status in (
        'not_required',
        'pending',
        'approved',
        'rejected',
        'changes_requested'
      )
    ),

  virus_scan_status text not null default 'pending'
    check (
      virus_scan_status in (
        'not_required',
        'pending',
        'scanning',
        'clean',
        'infected',
        'failed'
      )
    ),

  integrity_status text not null default 'pending'
    check (
      integrity_status in (
        'not_required',
        'pending',
        'verified',
        'mismatch',
        'failed'
      )
    ),

  processing_status text not null default 'pending'
    check (
      processing_status in (
        'not_required',
        'pending',
        'processing',
        'completed',
        'failed',
        'partial'
      )
    ),

  signature_status text not null default 'not_required'
    check (
      signature_status in (
        'not_required',
        'draft',
        'sent',
        'viewed',
        'partially_signed',
        'completed',
        'declined',
        'expired',
        'cancelled'
      )
    ),

  sensitivity_level text not null default 'internal'
    check (
      sensitivity_level in (
        'public',
        'internal',
        'confidential',
        'restricted',
        'highly_restricted'
      )
    ),

  issued_at timestamptz,
  effective_at timestamptz,
  expires_at timestamptz,
  reviewed_at timestamptz,
  approved_at timestamptz,
  archived_at timestamptz,
  deleted_at timestamptz,

  uploaded_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  deleted_by uuid references auth.users(id) on delete set null,

  source_module text,
  source_type text,
  source_id uuid,
  source_reference text,

  tags text[] not null default '{}',
  custom_metadata jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,document_code)
);

create index if not exists documents_entity_idx
  on public.documents (
    organization_id,
    entity_type,
    entity_id,
    created_at desc
  );

create index if not exists documents_lead_idx
  on public.documents (
    organization_id,
    lead_id,
    created_at desc
  );

create index if not exists documents_status_idx
  on public.documents (
    organization_id,
    lifecycle_status,
    approval_status,
    expires_at
  );

create unique index if not exists documents_storage_object_unique_idx
  on public.documents (
    storage_provider,
    storage_bucket,
    storage_path
  )
  where storage_path is not null
    and lifecycle_status <> 'deleted';

-- ============================================================
-- 6. DOCUMENT VERSIONS
-- ============================================================

create table if not exists public.document_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,

  version_number integer not null check (version_number > 0),
  version_label text,

  file_name text not null,
  mime_type text,
  file_extension text,
  file_size_bytes bigint,

  storage_provider text not null default 'supabase_storage',
  storage_bucket text,
  storage_path text not null,
  storage_object_id text,
  external_url text,

  checksum_algorithm text default 'sha256',
  checksum_value text,

  virus_scan_status text not null default 'pending',
  integrity_status text not null default 'pending',

  change_summary text,
  is_current boolean not null default false,
  is_immutable boolean not null default true,

  uploaded_by uuid references auth.users(id) on delete set null,
  uploaded_at timestamptz not null default now(),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (document_id,version_number)
);

create unique index if not exists document_versions_current_unique_idx
  on public.document_versions (document_id)
  where is_current = true;

create index if not exists document_versions_document_idx
  on public.document_versions (
    document_id,
    version_number desc
  );

-- ============================================================
-- 7. DOCUMENT TAGS
-- ============================================================

create table if not exists public.document_tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  tag_code text not null,
  tag_name text not null,
  description text,
  color_token text,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (organization_id,tag_code)
);

create table if not exists public.document_tag_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  tag_id uuid not null references public.document_tags(id) on delete cascade,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (document_id,tag_id)
);

-- ============================================================
-- 8. DOCUMENT RELATIONSHIPS
-- ============================================================

create table if not exists public.document_relationships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  parent_document_id uuid not null references public.documents(id) on delete cascade,
  child_document_id uuid not null references public.documents(id) on delete cascade,

  relationship_type text not null
    check (
      relationship_type in (
        'attachment',
        'replacement',
        'supplement',
        'translation',
        'supporting_document',
        'generated_from',
        'signed_copy',
        'related'
      )
    ),

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),

  check (parent_document_id <> child_document_id),

  unique (
    parent_document_id,
    child_document_id,
    relationship_type
  )
);

-- ============================================================
-- 9. ACCESS POLICIES
-- ============================================================

create table if not exists public.document_access_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid references public.documents(id) on delete cascade,
  folder_id uuid references public.document_folders(id) on delete cascade,

  principal_type text not null
    check (
      principal_type in (
        'user',
        'role',
        'team',
        'organization',
        'customer',
        'public',
        'service'
      )
    ),

  principal_user_id uuid references auth.users(id) on delete cascade,
  principal_role_id uuid,
  principal_team_id uuid references public.assignment_teams(id) on delete cascade,
  principal_customer_id uuid references public.customers(id) on delete cascade,
  principal_key text,

  permission_level text not null
    check (
      permission_level in (
        'view',
        'download',
        'comment',
        'edit',
        'share',
        'manage',
        'owner'
      )
    ),

  can_download boolean not null default false,
  can_share boolean not null default false,
  can_edit_metadata boolean not null default false,
  can_upload_version boolean not null default false,
  can_delete boolean not null default false,

  valid_from timestamptz not null default now(),
  valid_until timestamptz,

  status text not null default 'active'
    check (status in ('active','inactive','expired','revoked')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists document_access_policies_lookup_idx
  on public.document_access_policies (
    organization_id,
    document_id,
    folder_id,
    principal_type,
    status
  );

-- ============================================================
-- 10. SECURE SHARES AND DOWNLOAD TOKENS
-- ============================================================

create table if not exists public.document_shares (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete set null,

  share_type text not null default 'secure_link'
    check (share_type in ('secure_link','email','customer_portal','public_link','api')),

  token_hash text not null,
  token_prefix text,

  recipient_name text,
  recipient_email text,
  recipient_phone text,

  password_hash text,

  allow_download boolean not null default true,
  allow_preview boolean not null default true,
  maximum_downloads integer,
  download_count integer not null default 0,

  expires_at timestamptz,
  last_accessed_at timestamptz,

  status text not null default 'active'
    check (status in ('active','expired','revoked','consumed')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (token_hash)
);

create index if not exists document_shares_document_idx
  on public.document_shares (
    organization_id,
    document_id,
    status
  );

create table if not exists public.document_download_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete set null,
  document_share_id uuid references public.document_shares(id) on delete set null,

  user_id uuid references auth.users(id) on delete set null,

  access_type text not null default 'download'
    check (access_type in ('preview','download','stream','export')),

  ip_address inet,
  user_agent text,
  device_id text,

  success boolean not null default true,
  failure_reason text,

  bytes_transferred bigint,
  occurred_at timestamptz not null default now(),

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists document_download_events_document_idx
  on public.document_download_events (
    organization_id,
    document_id,
    occurred_at desc
  );

-- ============================================================
-- 11. UPLOAD SESSIONS
-- ============================================================

create table if not exists public.document_upload_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  document_id uuid references public.documents(id) on delete cascade,
  storage_bucket_id uuid references public.document_storage_buckets(id) on delete set null,

  upload_type text not null default 'single'
    check (upload_type in ('single','multipart','resumable','external_import')),

  status text not null default 'initiated'
    check (
      status in (
        'initiated',
        'uploading',
        'uploaded',
        'verifying',
        'completed',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  file_name text not null,
  mime_type text,
  expected_file_size_bytes bigint,
  uploaded_file_size_bytes bigint not null default 0,

  storage_path text,
  provider_upload_id text,

  expected_checksum text,
  calculated_checksum text,

  part_count integer,
  completed_parts jsonb not null default '[]',

  expires_at timestamptz,
  completed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_upload_sessions_status_idx
  on public.document_upload_sessions (
    organization_id,
    status,
    expires_at
  );

-- ============================================================
-- 12. PROCESSING JOBS
-- ============================================================

create table if not exists public.document_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete cascade,

  processing_type text not null
    check (
      processing_type in (
        'virus_scan',
        'checksum',
        'ocr',
        'text_extraction',
        'thumbnail',
        'preview',
        'classification',
        'entity_extraction',
        'redaction',
        'translation',
        'summarization',
        'embedding',
        'custom'
      )
    ),

  provider text,
  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,
  next_retry_at timestamptz,

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  input_data jsonb not null default '{}',
  result_data jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  started_at timestamptz,
  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_processing_jobs_queue_idx
  on public.document_processing_jobs (
    status,
    priority,
    next_retry_at,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 13. EXTRACTED CONTENT
-- ============================================================

create table if not exists public.document_extracted_content (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete cascade,

  extraction_type text not null
    check (
      extraction_type in (
        'plain_text',
        'ocr_text',
        'structured_data',
        'entities',
        'summary',
        'classification',
        'redacted_text',
        'translation',
        'embedding_reference'
      )
    ),

  language_code text,
  page_number integer,

  content_text text,
  content_json jsonb,

  confidence_score numeric(8,4),
  provider text,
  model_name text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create index if not exists document_extracted_content_document_idx
  on public.document_extracted_content (
    document_id,
    document_version_id,
    extraction_type
  );

-- ============================================================
-- 14. REVIEW AND APPROVAL
-- ============================================================

create table if not exists public.document_review_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete set null,

  review_type text not null default 'approval'
    check (
      review_type in (
        'approval',
        'verification',
        'compliance',
        'quality',
        'legal',
        'expiry_review',
        'custom'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'assigned',
        'in_review',
        'approved',
        'rejected',
        'changes_requested',
        'cancelled',
        'expired'
      )
    ),

  assigned_to uuid references auth.users(id) on delete set null,
  assigned_team_id uuid references public.assignment_teams(id) on delete set null,

  due_at timestamptz,

  decision text,
  decision_notes text,
  decision_data jsonb not null default '{}',

  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_review_tasks_queue_idx
  on public.document_review_tasks (
    organization_id,
    status,
    due_at,
    created_at
  );

-- ============================================================
-- 15. SIGNATURE ENVELOPES
-- ============================================================

create table if not exists public.document_signature_envelopes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,
  document_version_id uuid references public.document_versions(id) on delete set null,

  envelope_name text not null,
  provider text,
  provider_envelope_id text,

  signing_order_type text not null default 'sequential'
    check (signing_order_type in ('sequential','parallel','custom')),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'created',
        'sent',
        'viewed',
        'partially_signed',
        'completed',
        'declined',
        'cancelled',
        'expired',
        'failed'
      )
    ),

  email_subject text,
  email_message text,

  expires_at timestamptz,
  sent_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,

  signed_document_id uuid references public.documents(id) on delete set null,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.document_signature_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  envelope_id uuid not null references public.document_signature_envelopes(id) on delete cascade,

  recipient_order integer not null default 1,

  recipient_type text not null default 'signer'
    check (recipient_type in ('signer','approver','viewer','cc','witness')),

  user_id uuid references auth.users(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,

  recipient_name text not null,
  recipient_email text,
  recipient_phone text,

  provider_recipient_id text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'sent',
        'delivered',
        'viewed',
        'signed',
        'approved',
        'declined',
        'failed',
        'expired'
      )
    ),

  authentication_method text,
  authentication_data jsonb not null default '{}',

  sent_at timestamptz,
  viewed_at timestamptz,
  signed_at timestamptz,
  declined_at timestamptz,

  decline_reason text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (envelope_id,recipient_order)
);

-- ============================================================
-- 16. EXPIRY AND RETENTION
-- ============================================================

create table if not exists public.document_retention_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,

  category_id uuid references public.document_categories(id) on delete set null,
  entity_type text,

  retention_days integer not null check (retention_days > 0),
  archive_after_days integer,
  delete_after_days integer,

  legal_hold_override boolean not null default true,
  require_approval_before_delete boolean not null default true,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

create table if not exists public.document_expiry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,

  action_type text not null
    check (
      action_type in (
        'notify',
        'review',
        'expire',
        'archive',
        'delete'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  scheduled_at timestamptz not null,

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  result_data jsonb not null default '{}',
  error_data jsonb not null default '{}',

  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists document_expiry_queue_due_idx
  on public.document_expiry_queue (
    status,
    scheduled_at
  )
  where status = 'pending';

-- ============================================================
-- 17. EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.document_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  document_id uuid references public.documents(id) on delete set null,
  document_version_id uuid references public.document_versions(id) on delete set null,

  event_name text not null,
  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'workflow_engine',
        'notification_engine',
        'n8n',
        'webhook',
        'analytics',
        'audit'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'delivered',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  idempotency_key text,
  correlation_id text,
  trace_id text,

  payload jsonb not null default '{}',
  headers jsonb not null default '{}',

  available_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists document_event_outbox_idempotency_idx
  on public.document_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists document_event_outbox_queue_idx
  on public.document_event_outbox (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

create table if not exists public.document_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  document_id uuid references public.documents(id) on delete set null,
  document_version_id uuid references public.document_versions(id) on delete set null,
  processing_job_id uuid references public.document_processing_jobs(id) on delete set null,
  signature_envelope_id uuid references public.document_signature_envelopes(id) on delete set null,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,

  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists document_logs_org_created_idx
  on public.document_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 18. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'document_categories',
    'document_storage_buckets',
    'document_folders',
    'documents',
    'document_shares',
    'document_upload_sessions',
    'document_processing_jobs',
    'document_review_tasks',
    'document_signature_envelopes',
    'document_signature_recipients',
    'document_retention_policies',
    'document_expiry_queue',
    'document_event_outbox'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      target_table,
      target_table
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      target_table,
      target_table
    );
  end loop;
end;
$$;

-- ============================================================
-- 19. CREATE DOCUMENT
-- ============================================================

create or replace function public.create_document_record(
  requested_organization_id uuid,
  requested_document_name text,
  requested_category_id uuid default null,
  requested_folder_id uuid default null,
  requested_storage_bucket_id uuid default null,
  requested_document_code text default null,
  requested_description text default null,
  requested_mime_type text default null,
  requested_file_size_bytes bigint default null,
  requested_storage_bucket text default null,
  requested_storage_path text default null,
  requested_entity_type text default null,
  requested_entity_id uuid default null,
  requested_entity_reference text default null,
  requested_lead_id uuid default null,
  requested_customer_id uuid default null,
  requested_booking_id uuid default null,
  requested_site_visit_id uuid default null,
  requested_visibility text default 'private',
  requested_sensitivity_level text default 'internal',
  requested_source_module text default null,
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_source_reference text default null,
  requested_tags text[] default '{}',
  requested_custom_metadata jsonb default '{}'::jsonb
)
returns public.documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  document_record public.documents;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'document.upload'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.documents (
    organization_id,
    folder_id,
    category_id,
    storage_bucket_id,
    document_code,
    document_name,
    description,
    mime_type,
    file_extension,
    file_size_bytes,
    storage_bucket,
    storage_path,
    entity_type,
    entity_id,
    entity_reference,
    lead_id,
    customer_id,
    booking_id,
    site_visit_id,
    visibility,
    lifecycle_status,
    sensitivity_level,
    uploaded_by,
    source_module,
    source_type,
    source_id,
    source_reference,
    tags,
    custom_metadata
  )
  values (
    requested_organization_id,
    requested_folder_id,
    requested_category_id,
    requested_storage_bucket_id,
    coalesce(
      requested_document_code,
      'DOC-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12))
    ),
    requested_document_name,
    requested_description,
    requested_mime_type,
    case
      when requested_document_name like '%.%'
        then lower(split_part(requested_document_name,'.',array_length(string_to_array(requested_document_name,'.'),1)))
      else null
    end,
    requested_file_size_bytes,
    requested_storage_bucket,
    requested_storage_path,
    requested_entity_type,
    requested_entity_id,
    requested_entity_reference,
    requested_lead_id,
    requested_customer_id,
    requested_booking_id,
    requested_site_visit_id,
    requested_visibility,
    case
      when requested_storage_path is null then 'draft'
      else 'processing'
    end,
    requested_sensitivity_level,
    auth.uid(),
    requested_source_module,
    requested_source_type,
    requested_source_id,
    requested_source_reference,
    coalesce(requested_tags,'{}'::text[]),
    coalesce(requested_custom_metadata,'{}'::jsonb)
  )
  returning * into document_record;

  return document_record;
end;
$$;

revoke all
on function public.create_document_record(
  uuid,text,uuid,uuid,uuid,text,text,text,bigint,text,text,text,uuid,text,
  uuid,uuid,uuid,uuid,text,text,text,text,uuid,text,text[],jsonb
)
from public;

grant execute
on function public.create_document_record(
  uuid,text,uuid,uuid,uuid,text,text,text,bigint,text,text,text,uuid,text,
  uuid,uuid,uuid,uuid,text,text,text,text,uuid,text,text[],jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. ADD DOCUMENT VERSION
-- ============================================================

create or replace function public.add_document_version(
  requested_document_id uuid,
  requested_file_name text,
  requested_storage_path text,
  requested_mime_type text default null,
  requested_file_size_bytes bigint default null,
  requested_storage_bucket text default null,
  requested_storage_object_id text default null,
  requested_checksum_value text default null,
  requested_change_summary text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.document_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  document_record public.documents;
  next_version integer;
  version_record public.document_versions;
begin
  select *
  into document_record
  from public.documents
  where id = requested_document_id
  for update;

  if not found then
    raise exception 'Document not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      document_record.organization_id,
      'document.update'
    ) then
    raise exception 'Permission denied';
  end if;

  select coalesce(max(version_number),0) + 1
  into next_version
  from public.document_versions
  where document_id = document_record.id;

  update public.document_versions
  set is_current = false
  where document_id = document_record.id
    and is_current = true;

  insert into public.document_versions (
    organization_id,
    document_id,
    version_number,
    version_label,
    file_name,
    mime_type,
    file_extension,
    file_size_bytes,
    storage_provider,
    storage_bucket,
    storage_path,
    storage_object_id,
    checksum_value,
    virus_scan_status,
    integrity_status,
    change_summary,
    is_current,
    uploaded_by,
    metadata
  )
  values (
    document_record.organization_id,
    document_record.id,
    next_version,
    'v' || next_version::text,
    requested_file_name,
    requested_mime_type,
    case
      when requested_file_name like '%.%'
        then lower(split_part(requested_file_name,'.',array_length(string_to_array(requested_file_name,'.'),1)))
      else null
    end,
    requested_file_size_bytes,
    document_record.storage_provider,
    coalesce(requested_storage_bucket,document_record.storage_bucket),
    requested_storage_path,
    requested_storage_object_id,
    requested_checksum_value,
    'pending',
    'pending',
    requested_change_summary,
    true,
    auth.uid(),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into version_record;

  update public.documents
  set
    current_version_number = next_version,
    current_version_id = version_record.id,
    document_name = requested_file_name,
    mime_type = requested_mime_type,
    file_extension = version_record.file_extension,
    file_size_bytes = requested_file_size_bytes,
    storage_bucket = version_record.storage_bucket,
    storage_path = requested_storage_path,
    storage_object_id = requested_storage_object_id,
    checksum_value = requested_checksum_value,
    lifecycle_status = 'processing',
    virus_scan_status = 'pending',
    integrity_status = 'pending',
    processing_status = 'pending',
    updated_at = now()
  where id = document_record.id;

  return version_record;
end;
$$;

revoke all
on function public.add_document_version(
  uuid,text,text,text,bigint,text,text,text,text,jsonb
)
from public;

grant execute
on function public.add_document_version(
  uuid,text,text,text,bigint,text,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 21. QUEUE STANDARD PROCESSING
-- ============================================================

create or replace function public.queue_document_standard_processing(
  requested_document_id uuid,
  requested_document_version_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  document_record public.documents;
  version_value uuid;
  process_type text;
  inserted_count integer := 0;
begin
  select *
  into document_record
  from public.documents
  where id = requested_document_id;

  if not found then
    raise exception 'Document not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      document_record.organization_id,
      'document.manage_processing'
    ) then
    raise exception 'Permission denied';
  end if;

  version_value := coalesce(
    requested_document_version_id,
    document_record.current_version_id
  );

  foreach process_type in array array[
    'virus_scan',
    'checksum',
    'text_extraction',
    'thumbnail',
    'preview'
  ]
  loop
    insert into public.document_processing_jobs (
      organization_id,
      document_id,
      document_version_id,
      processing_type,
      status,
      priority,
      maximum_attempts,
      input_data
    )
    values (
      document_record.organization_id,
      document_record.id,
      version_value,
      process_type,
      'queued',
      case process_type
        when 'virus_scan' then 10
        when 'checksum' then 20
        else 100
      end,
      5,
      jsonb_build_object(
        'storage_bucket',
        document_record.storage_bucket,
        'storage_path',
        document_record.storage_path
      )
    );

    inserted_count := inserted_count + 1;
  end loop;

  update public.documents
  set
    lifecycle_status = 'processing',
    processing_status = 'processing',
    updated_at = now()
  where id = document_record.id;

  return inserted_count;
end;
$$;

revoke all
on function public.queue_document_standard_processing(uuid,uuid)
from public;

grant execute
on function public.queue_document_standard_processing(uuid,uuid)
to authenticated,service_role;

-- ============================================================
-- 22. CLAIM PROCESSING JOB
-- ============================================================

create or replace function public.claim_document_processing_job(
  requested_worker_id text,
  requested_processing_type text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.document_processing_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.document_processing_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim document-processing jobs';
  end if;

  select *
  into job_record
  from public.document_processing_jobs j
  where j.status in ('queued','failed')
    and (j.next_retry_at is null or j.next_retry_at <= now())
    and j.attempts < j.maximum_attempts
    and (
      requested_processing_type is null
      or j.processing_type = requested_processing_type
    )
    and (
      requested_organization_id is null
      or j.organization_id = requested_organization_id
    )
  order by j.priority,j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.document_processing_jobs
  set
    status = 'claimed',
    attempts = attempts + 1,
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    started_at = coalesce(started_at,now()),
    updated_at = now()
  where id = job_record.id
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.claim_document_processing_job(text,text,uuid,integer)
from public;

grant execute
on function public.claim_document_processing_job(text,text,uuid,integer)
to service_role;

-- ============================================================
-- 23. COMPLETE PROCESSING JOB
-- ============================================================

create or replace function public.complete_document_processing_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.document_processing_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.document_processing_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete document-processing jobs';
  end if;

  select *
  into job_record
  from public.document_processing_jobs
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Document-processing job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid document-processing lock token';
  end if;

  update public.document_processing_jobs
  set
    status = 'completed',
    result_data = coalesce(requested_result_data,'{}'::jsonb),
    completed_at = now(),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = job_record.id
  returning * into job_record;

  if job_record.processing_type = 'virus_scan' then
    update public.documents
    set
      virus_scan_status = coalesce(
        requested_result_data->>'status',
        'clean'
      ),
      lifecycle_status = case
        when coalesce(requested_result_data->>'status','clean') = 'infected'
          then 'quarantined'
        else lifecycle_status
      end,
      updated_at = now()
    where id = job_record.document_id;
  elsif job_record.processing_type = 'checksum' then
    update public.documents
    set
      integrity_status = coalesce(
        requested_result_data->>'status',
        'verified'
      ),
      checksum_value = coalesce(
        requested_result_data->>'checksum',
        checksum_value
      ),
      updated_at = now()
    where id = job_record.document_id;
  end if;

  if not exists (
    select 1
    from public.document_processing_jobs p
    where p.document_id = job_record.document_id
      and p.status in ('queued','claimed','processing','failed')
  ) then
    update public.documents
    set
      processing_status = 'completed',
      lifecycle_status = case
        when virus_scan_status = 'infected' then 'quarantined'
        when approval_status = 'pending' then 'pending_review'
        else 'active'
      end,
      updated_at = now()
    where id = job_record.document_id;
  end if;

  return job_record;
end;
$$;

revoke all
on function public.complete_document_processing_job(uuid,text,jsonb)
from public;

grant execute
on function public.complete_document_processing_job(uuid,text,jsonb)
to service_role;

-- ============================================================
-- 24. REVIEW DECISION
-- ============================================================

create or replace function public.decide_document_review(
  requested_review_task_id uuid,
  requested_decision text,
  requested_notes text default null,
  requested_decision_data jsonb default '{}'::jsonb
)
returns public.document_review_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_record public.document_review_tasks;
begin
  if requested_decision not in ('approved','rejected','changes_requested') then
    raise exception 'Invalid document-review decision';
  end if;

  select *
  into task_record
  from public.document_review_tasks
  where id = requested_review_task_id
  for update;

  if not found then
    raise exception 'Document review task not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from task_record.assigned_to
    and not public.has_organization_permission(
      task_record.organization_id,
      'document.approve'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.document_review_tasks
  set
    status = requested_decision,
    decision = requested_decision,
    decision_notes = requested_notes,
    decision_data = coalesce(requested_decision_data,'{}'::jsonb),
    decided_by = auth.uid(),
    decided_at = now(),
    updated_at = now()
  where id = task_record.id
  returning * into task_record;

  update public.documents
  set
    approval_status = requested_decision,
    lifecycle_status = case
      when requested_decision = 'approved'
        and virus_scan_status in ('clean','not_required')
        and integrity_status in ('verified','not_required')
        then 'active'
      when requested_decision = 'rejected' then 'rejected'
      else 'pending_review'
    end,
    approved_by = case
      when requested_decision = 'approved' then auth.uid()
      else approved_by
    end,
    approved_at = case
      when requested_decision = 'approved' then now()
      else approved_at
    end,
    reviewed_at = now(),
    updated_at = now()
  where id = task_record.document_id;

  return task_record;
end;
$$;

revoke all
on function public.decide_document_review(uuid,text,text,jsonb)
from public;

grant execute
on function public.decide_document_review(uuid,text,text,jsonb)
to authenticated,service_role;

-- ============================================================
-- 25. CREATE SECURE SHARE
-- ============================================================

create or replace function public.create_document_share(
  requested_document_id uuid,
  requested_document_version_id uuid default null,
  requested_recipient_name text default null,
  requested_recipient_email text default null,
  requested_recipient_phone text default null,
  requested_allow_download boolean default true,
  requested_allow_preview boolean default true,
  requested_maximum_downloads integer default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  document_record public.documents;
  raw_token text := replace(gen_random_uuid()::text,'-','')
    || replace(gen_random_uuid()::text,'-','');
  token_hash_value text;
  share_record public.document_shares;
begin
  select *
  into document_record
  from public.documents
  where id = requested_document_id;

  if not found then
    raise exception 'Document not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      document_record.organization_id,
      'document.share'
    ) then
    raise exception 'Permission denied';
  end if;

  token_hash_value := encode(
    digest(raw_token,'sha256'),
    'hex'
  );

  insert into public.document_shares (
    organization_id,
    document_id,
    document_version_id,
    share_type,
    token_hash,
    token_prefix,
    recipient_name,
    recipient_email,
    recipient_phone,
    allow_download,
    allow_preview,
    maximum_downloads,
    expires_at,
    status,
    metadata,
    created_by
  )
  values (
    document_record.organization_id,
    document_record.id,
    coalesce(
      requested_document_version_id,
      document_record.current_version_id
    ),
    'secure_link',
    token_hash_value,
    left(raw_token,8),
    requested_recipient_name,
    requested_recipient_email,
    requested_recipient_phone,
    requested_allow_download,
    requested_allow_preview,
    requested_maximum_downloads,
    requested_expires_at,
    'active',
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid()
  )
  returning * into share_record;

  return jsonb_build_object(
    'share_id',
    share_record.id,
    'token',
    raw_token,
    'token_prefix',
    share_record.token_prefix,
    'expires_at',
    share_record.expires_at
  );
end;
$$;

revoke all
on function public.create_document_share(
  uuid,uuid,text,text,text,boolean,boolean,integer,timestamptz,jsonb
)
from public;

grant execute
on function public.create_document_share(
  uuid,uuid,text,text,text,boolean,boolean,integer,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 26. VALIDATE SECURE SHARE
-- ============================================================

create or replace function public.validate_document_share(
  requested_token text,
  requested_access_type text default 'preview',
  requested_ip_address inet default null,
  requested_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_hash_value text;
  share_record public.document_shares;
  document_record public.documents;
begin
  token_hash_value := encode(
    digest(requested_token,'sha256'),
    'hex'
  );

  select *
  into share_record
  from public.document_shares
  where token_hash = token_hash_value
  for update;

  if not found then
    return jsonb_build_object(
      'valid',
      false,
      'reason',
      'Invalid share token'
    );
  end if;

  if share_record.status <> 'active'
    or (
      share_record.expires_at is not null
      and share_record.expires_at <= now()
    )
    or (
      share_record.maximum_downloads is not null
      and share_record.download_count >= share_record.maximum_downloads
      and requested_access_type = 'download'
    ) then
    return jsonb_build_object(
      'valid',
      false,
      'reason',
      'Share token expired, revoked or exhausted'
    );
  end if;

  if requested_access_type = 'download'
    and not share_record.allow_download then
    return jsonb_build_object(
      'valid',
      false,
      'reason',
      'Download is not allowed'
    );
  end if;

  if requested_access_type = 'preview'
    and not share_record.allow_preview then
    return jsonb_build_object(
      'valid',
      false,
      'reason',
      'Preview is not allowed'
    );
  end if;

  select *
  into document_record
  from public.documents
  where id = share_record.document_id;

  insert into public.document_download_events (
    organization_id,
    document_id,
    document_version_id,
    document_share_id,
    access_type,
    ip_address,
    user_agent,
    success
  )
  values (
    share_record.organization_id,
    share_record.document_id,
    share_record.document_version_id,
    share_record.id,
    requested_access_type,
    requested_ip_address,
    requested_user_agent,
    true
  );

  update public.document_shares
  set
    download_count = download_count
      + case when requested_access_type = 'download' then 1 else 0 end,
    last_accessed_at = now(),
    status = case
      when maximum_downloads is not null
        and download_count
          + case when requested_access_type = 'download' then 1 else 0 end
          >= maximum_downloads
        then 'consumed'
      else status
    end,
    updated_at = now()
  where id = share_record.id;

  return jsonb_build_object(
    'valid',
    true,
    'document_id',
    document_record.id,
    'document_name',
    document_record.document_name,
    'mime_type',
    document_record.mime_type,
    'storage_bucket',
    document_record.storage_bucket,
    'storage_path',
    document_record.storage_path,
    'version_id',
    share_record.document_version_id,
    'allow_download',
    share_record.allow_download,
    'allow_preview',
    share_record.allow_preview
  );
end;
$$;

revoke all
on function public.validate_document_share(text,text,inet,text)
from public;

grant execute
on function public.validate_document_share(text,text,inet,text)
to anon,authenticated,service_role;

-- ============================================================
-- 27. PUBLISH DOCUMENT EVENT
-- ============================================================

create or replace function public.publish_document_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_document_id uuid default null,
  requested_document_version_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.document_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.document_event_outbox;
  created_event public.document_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.document_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.document_event_outbox (
    organization_id,
    document_id,
    document_version_id,
    event_name,
    destination,
    status,
    priority,
    idempotency_key,
    correlation_id,
    trace_id,
    payload,
    available_at
  )
  values (
    requested_organization_id,
    requested_document_id,
    requested_document_version_id,
    requested_event_name,
    requested_destination,
    'pending',
    requested_priority,
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all
on function public.publish_document_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_document_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 28. DOCUMENT STATUS EVENT TRIGGER
-- ============================================================

create or replace function public.emit_document_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op = 'UPDATE'
    and new.lifecycle_status is not distinct from old.lifecycle_status
    and new.approval_status is not distinct from old.approval_status
    and new.signature_status is not distinct from old.signature_status
    and new.processing_status is not distinct from old.processing_status then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',new.organization_id,
    'document_id',new.id,
    'document_code',new.document_code,
    'document_name',new.document_name,
    'entity_type',new.entity_type,
    'entity_id',new.entity_id,
    'lead_id',new.lead_id,
    'customer_id',new.customer_id,
    'booking_id',new.booking_id,
    'site_visit_id',new.site_visit_id,
    'lifecycle_status',new.lifecycle_status,
    'approval_status',new.approval_status,
    'virus_scan_status',new.virus_scan_status,
    'integrity_status',new.integrity_status,
    'processing_status',new.processing_status,
    'signature_status',new.signature_status,
    'expires_at',new.expires_at
  );

  perform public.publish_document_event(
    new.organization_id,
    'document.' || new.lifecycle_status,
    payload_data,
    'automation_engine',
    new.id,
    new.current_version_id,
    case
      when new.lifecycle_status in ('quarantined','rejected','expired') then 10
      else 50
    end,
    'document-automation:' || new.id::text || ':' || new.lifecycle_status,
    new.id::text,
    null,
    now()
  );

  perform public.publish_document_event(
    new.organization_id,
    'document.' || new.lifecycle_status,
    payload_data,
    'notification_engine',
    new.id,
    new.current_version_id,
    50,
    'document-notification:' || new.id::text || ':' || new.lifecycle_status,
    new.id::text,
    null,
    now()
  );

  return new;
end;
$$;

drop trigger if exists documents_emit_events
on public.documents;

create trigger documents_emit_events
after insert or update
on public.documents
for each row
execute function public.emit_document_events();

-- ============================================================
-- 29. ANALYTICS VIEWS
-- ============================================================

create or replace view public.document_repository_dashboard
with (security_invoker = true)
as
select
  organization_id,

  count(*) as total_documents,

  count(*) filter (
    where lifecycle_status = 'active'
  ) as active_documents,

  count(*) filter (
    where lifecycle_status = 'pending_review'
  ) as pending_review_documents,

  count(*) filter (
    where lifecycle_status = 'quarantined'
  ) as quarantined_documents,

  count(*) filter (
    where lifecycle_status = 'expired'
      or (
        expires_at is not null
        and expires_at <= now()
      )
  ) as expired_documents,

  count(*) filter (
    where expires_at is not null
      and expires_at > now()
      and expires_at <= now() + interval '30 days'
  ) as expiring_30_days,

  coalesce(sum(file_size_bytes),0) as total_storage_bytes,

  max(created_at) as latest_upload_at

from public.documents
where lifecycle_status <> 'deleted'
group by organization_id;

create or replace view public.document_category_dashboard
with (security_invoker = true)
as
select
  d.organization_id,
  c.category_code,
  c.category_name,

  count(d.id) as document_count,

  count(d.id) filter (
    where d.lifecycle_status = 'active'
  ) as active_count,

  count(d.id) filter (
    where d.approval_status = 'pending'
  ) as pending_approval_count,

  count(d.id) filter (
    where d.signature_status in ('sent','viewed','partially_signed')
  ) as pending_signature_count,

  coalesce(sum(d.file_size_bytes),0) as storage_bytes

from public.documents d
left join public.document_categories c
  on c.id = d.category_id
where d.lifecycle_status <> 'deleted'
group by
  d.organization_id,
  c.category_code,
  c.category_name;

create or replace view public.document_processing_dashboard
with (security_invoker = true)
as
select
  organization_id,
  processing_type,

  count(*) as total_jobs,

  count(*) filter (
    where status = 'completed'
  ) as completed_jobs,

  count(*) filter (
    where status = 'failed'
  ) as failed_jobs,

  count(*) filter (
    where status in ('queued','claimed','processing')
  ) as pending_jobs,

  round(
    count(*) filter (
      where status = 'completed'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as success_rate,

  max(completed_at) as latest_completion_at

from public.document_processing_jobs
group by organization_id,processing_type;

create or replace view public.document_access_dashboard
with (security_invoker = true)
as
select
  organization_id,
  document_id,

  count(*) as access_events,

  count(*) filter (
    where access_type = 'preview'
  ) as preview_count,

  count(*) filter (
    where access_type = 'download'
  ) as download_count,

  count(*) filter (
    where success = false
  ) as failed_access_count,

  max(occurred_at) as latest_access_at

from public.document_download_events
group by organization_id,document_id;

grant select
on
  public.document_repository_dashboard,
  public.document_category_dashboard,
  public.document_processing_dashboard,
  public.document_access_dashboard
to authenticated,service_role;

-- ============================================================
-- 30. HEALTH CHECK
-- ============================================================

create or replace function public.get_document_engine_health(
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'document.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'total_documents',(
      select count(*)
      from public.documents d
      where (
        requested_organization_id is null
        or d.organization_id = requested_organization_id
      )
        and d.lifecycle_status <> 'deleted'
    ),

    'pending_processing_jobs',(
      select count(*)
      from public.document_processing_jobs j
      where j.status in ('queued','claimed','processing','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'quarantined_documents',(
      select count(*)
      from public.documents d
      where d.lifecycle_status = 'quarantined'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'pending_reviews',(
      select count(*)
      from public.document_review_tasks r
      where r.status in ('pending','assigned','in_review')
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'pending_signatures',(
      select count(*)
      from public.document_signature_envelopes e
      where e.status in ('sent','viewed','partially_signed')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'expiring_30_days',(
      select count(*)
      from public.documents d
      where d.expires_at > now()
        and d.expires_at <= now() + interval '30 days'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'pending_expiry_actions',(
      select count(*)
      from public.document_expiry_queue q
      where q.status = 'pending'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.document_event_outbox e
      where e.status in ('pending','failed')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_document_engine_health(uuid)
from public;

grant execute
on function public.get_document_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 31. RLS
-- ============================================================

alter table public.document_categories enable row level security;
alter table public.document_storage_buckets enable row level security;
alter table public.document_folders enable row level security;
alter table public.documents enable row level security;
alter table public.document_versions enable row level security;
alter table public.document_tags enable row level security;
alter table public.document_tag_links enable row level security;
alter table public.document_relationships enable row level security;
alter table public.document_access_policies enable row level security;
alter table public.document_shares enable row level security;
alter table public.document_download_events enable row level security;
alter table public.document_upload_sessions enable row level security;
alter table public.document_processing_jobs enable row level security;
alter table public.document_extracted_content enable row level security;
alter table public.document_review_tasks enable row level security;
alter table public.document_signature_envelopes enable row level security;
alter table public.document_signature_recipients enable row level security;
alter table public.document_retention_policies enable row level security;
alter table public.document_expiry_queue enable row level security;
alter table public.document_event_outbox enable row level security;
alter table public.document_logs enable row level security;

drop policy if exists document_categories_authenticated_select
on public.document_categories;

create policy document_categories_authenticated_select
on public.document_categories
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'document.view'
  )
  or public.has_organization_permission(
    organization_id,
    'document.view_all'
  )
);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'document_storage_buckets',
    'document_folders',
    'documents',
    'document_versions',
    'document_tags',
    'document_tag_links',
    'document_relationships',
    'document_access_policies',
    'document_shares',
    'document_download_events',
    'document_upload_sessions',
    'document_processing_jobs',
    'document_extracted_content',
    'document_review_tasks',
    'document_signature_envelopes',
    'document_signature_recipients',
    'document_retention_policies',
    'document_expiry_queue',
    'document_event_outbox',
    'document_logs'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select
       to authenticated
       using (
         public.has_organization_permission(
           organization_id,
           ''document.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''document.view_all''
         )
       )',
      target_table,target_table
    );

    execute format(
      'drop policy if exists %I_service_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_service_policy
       on public.%I
       for all
       to service_role
       using (true)
       with check (true)',
      target_table,target_table
    );
  end loop;
end;
$$;

drop policy if exists documents_write_policy
on public.documents;

create policy documents_write_policy
on public.documents
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'document.update'
  )
  or uploaded_by = auth.uid()
)
with check (
  public.has_organization_permission(
    organization_id,
    'document.upload'
  )
  or public.has_organization_permission(
    organization_id,
    'document.update'
  )
);

drop policy if exists document_folders_write_policy
on public.document_folders;

create policy document_folders_write_policy
on public.document_folders
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'document.manage_folders'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'document.manage_folders'
  )
);

drop policy if exists document_access_policies_write_policy
on public.document_access_policies;

create policy document_access_policies_write_policy
on public.document_access_policies
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'document.manage_access'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'document.manage_access'
  )
);

-- ============================================================
-- 32. GRANTS
-- ============================================================

grant select
on
  public.document_categories,
  public.document_storage_buckets,
  public.document_folders,
  public.documents,
  public.document_versions,
  public.document_tags,
  public.document_tag_links,
  public.document_relationships,
  public.document_access_policies,
  public.document_shares,
  public.document_download_events,
  public.document_upload_sessions,
  public.document_processing_jobs,
  public.document_extracted_content,
  public.document_review_tasks,
  public.document_signature_envelopes,
  public.document_signature_recipients,
  public.document_retention_policies,
  public.document_expiry_queue,
  public.document_event_outbox,
  public.document_logs
to authenticated;

grant insert,update,delete
on
  public.document_categories,
  public.document_storage_buckets,
  public.document_folders,
  public.documents,
  public.document_versions,
  public.document_tags,
  public.document_tag_links,
  public.document_relationships,
  public.document_access_policies,
  public.document_shares,
  public.document_upload_sessions,
  public.document_review_tasks,
  public.document_signature_envelopes,
  public.document_signature_recipients,
  public.document_retention_policies
to authenticated;

grant all
on
  public.document_categories,
  public.document_storage_buckets,
  public.document_folders,
  public.documents,
  public.document_versions,
  public.document_tags,
  public.document_tag_links,
  public.document_relationships,
  public.document_access_policies,
  public.document_shares,
  public.document_download_events,
  public.document_upload_sessions,
  public.document_processing_jobs,
  public.document_extracted_content,
  public.document_review_tasks,
  public.document_signature_envelopes,
  public.document_signature_recipients,
  public.document_retention_policies,
  public.document_expiry_queue,
  public.document_event_outbox,
  public.document_logs
to service_role;

-- ============================================================
-- 33. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'document_categories',
    'document_storage_buckets',
    'document_folders',
    'documents',
    'document_versions',
    'document_tags',
    'document_tag_links',
    'document_relationships',
    'document_access_policies',
    'document_shares',
    'document_download_events',
    'document_upload_sessions',
    'document_processing_jobs',
    'document_extracted_content',
    'document_review_tasks',
    'document_signature_envelopes',
    'document_signature_recipients',
    'document_retention_policies',
    'document_expiry_queue',
    'document_event_outbox',
    'document_logs'
  ]
  loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'table:' || item
      );
    end if;
  end loop;

  foreach item in array array[
    'create_document_record',
    'add_document_version',
    'queue_document_standard_processing',
    'claim_document_processing_job',
    'complete_document_processing_job',
    'decide_document_review',
    'create_document_share',
    'validate_document_share',
    'publish_document_event',
    'get_document_engine_health'
  ]
  loop
    if not exists (
      select 1
      from information_schema.routines
      where routine_schema = 'public'
        and routine_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'function:' || item
      );
    end if;
  end loop;

  if cardinality(missing_items) > 0 then
    raise exception
      '018 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 34. MIGRATION AUDIT
-- ============================================================

insert into public.document_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.018.completed',
  'Document Management Engine migration 018 completed',
  jsonb_build_object(
    'migration',
    '018_document_management_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'categories',
      'storage_buckets',
      'folders',
      'documents',
      'versions',
      'tags',
      'relationships',
      'access_policies',
      'secure_shares',
      'downloads',
      'upload_sessions',
      'processing',
      'ocr_and_extraction',
      'review_and_approval',
      'digital_signatures',
      'retention_and_expiry',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.document_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.018.completed'
);

commit;