-- ============================================================
-- SalesSetu Enterprise
-- Migration 025: AI Intelligence Engine
-- PostgreSQL / Supabase
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- 1. Permissions
insert into public.permissions(module,action,code,description)
select v.module,v.action,v.code,v.description
from (values
('ai_intelligence','view','ai_intelligence.view','View AI intelligence data'),
('ai_intelligence','view_all','ai_intelligence.view_all','View all AI intelligence data'),
('ai_intelligence','manage_providers','ai_intelligence.manage_providers','Manage AI providers'),
('ai_intelligence','manage_models','ai_intelligence.manage_models','Manage AI models'),
('ai_intelligence','manage_agents','ai_intelligence.manage_agents','Manage AI agents'),
('ai_intelligence','manage_skills','ai_intelligence.manage_skills','Manage AI skills'),
('ai_intelligence','manage_prompts','ai_intelligence.manage_prompts','Manage AI prompts'),
('ai_intelligence','manage_memory','ai_intelligence.manage_memory','Manage AI memory'),
('ai_intelligence','manage_knowledge','ai_intelligence.manage_knowledge','Manage AI knowledge bases'),
('ai_intelligence','manage_rag','ai_intelligence.manage_rag','Manage RAG pipelines'),
('ai_intelligence','execute','ai_intelligence.execute','Execute AI tasks'),
('ai_intelligence','approve_actions','ai_intelligence.approve_actions','Approve AI actions'),
('ai_intelligence','manage_budgets','ai_intelligence.manage_budgets','Manage AI budgets'),
('ai_intelligence','view_sensitive','ai_intelligence.view_sensitive','View sensitive AI content'),
('ai_intelligence','view_logs','ai_intelligence.view_logs','View AI logs'),
('ai_intelligence','view_analytics','ai_intelligence.view_analytics','View AI analytics')
) as v(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=v.code);

-- 2. Providers and models
create table if not exists public.ai_intelligence_providers(
 id uuid primary key default gen_random_uuid(),
 provider_code text not null unique,
 provider_name text not null,
 provider_type text not null check(provider_type in('llm','embedding','vision','speech','reranker','multimodal','custom')),
 base_url text,
 authentication_type text not null default 'api_key',
 supported_capabilities text[] not null default '{}',
 status text not null default 'active' check(status in('active','inactive','degraded','deprecated','archived')),
 is_system_provider boolean not null default true,
 configuration_schema jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

insert into public.ai_intelligence_providers(provider_code,provider_name,provider_type,base_url,authentication_type,supported_capabilities,is_system_provider)
values
('openai','OpenAI','multimodal','https://api.openai.com','api_key',array['chat','reasoning','embeddings','vision','audio','tools'],true),
('anthropic','Anthropic','llm','https://api.anthropic.com','api_key',array['chat','reasoning','vision','tools'],true),
('google_gemini','Google Gemini','multimodal','https://generativelanguage.googleapis.com','api_key',array['chat','reasoning','vision','embeddings','tools'],true),
('azure_openai','Azure OpenAI','multimodal',null,'api_key',array['chat','embeddings','vision','audio','tools'],true),
('groq','Groq','llm','https://api.groq.com','api_key',array['chat','reasoning'],true),
('cohere','Cohere','multimodal','https://api.cohere.com','api_key',array['chat','embeddings','rerank'],true),
('custom_ai','Custom AI Provider','custom',null,'custom',array['custom'],true)
on conflict(provider_code) do nothing;

create table if not exists public.ai_intelligence_provider_connections(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 provider_id uuid not null references public.ai_intelligence_providers(id) on delete restrict,
 connection_code text not null,
 connection_name text not null,
 environment text not null default 'production' check(environment in('development','staging','production')),
 credential_reference text,
 base_url_override text,
 api_version text,
 region text,
 status text not null default 'inactive' check(status in('inactive','pending','active','degraded','error','expired','revoked','archived')),
 enabled boolean not null default false,
 health_status text not null default 'unknown' check(health_status in('unknown','healthy','degraded','unhealthy','disabled')),
 last_health_check_at timestamptz,
 last_success_at timestamptz,
 last_failure_at timestamptz,
 last_error_code text,
 last_error_message text,
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,connection_code)
);

create table if not exists public.ai_intelligence_models(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 provider_id uuid not null references public.ai_intelligence_providers(id) on delete restrict,
 provider_connection_id uuid references public.ai_intelligence_provider_connections(id) on delete set null,
 model_code text not null,
 model_name text not null,
 provider_model_name text not null,
 model_type text not null check(model_type in('chat','reasoning','embedding','vision','speech_to_text','text_to_speech','reranker','multimodal','custom')),
 context_window integer,
 max_output_tokens integer,
 embedding_dimensions integer,
 input_cost_per_million numeric(18,8),
 output_cost_per_million numeric(18,8),
 cached_input_cost_per_million numeric(18,8),
 supports_tools boolean not null default false,
 supports_json_mode boolean not null default false,
 supports_streaming boolean not null default true,
 supports_vision boolean not null default false,
 supports_audio boolean not null default false,
 default_temperature numeric(8,4),
 default_top_p numeric(8,4),
 status text not null default 'active' check(status in('active','inactive','testing','deprecated','archived')),
 is_default boolean not null default false,
 is_system_model boolean not null default false,
 capabilities jsonb not null default '{}',
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,model_code)
);
create unique index if not exists ai_models_system_unique_idx on public.ai_intelligence_models(model_code) where organization_id is null;

create table if not exists public.ai_intelligence_routing_policies(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 policy_code text not null,
 policy_name text not null,
 task_type text not null,
 primary_model_id uuid references public.ai_intelligence_models(id) on delete set null,
 fallback_model_ids uuid[] not null default '{}',
 routing_strategy text not null default 'priority' check(routing_strategy in('priority','cost_optimized','quality_optimized','latency_optimized','round_robin','custom')),
 maximum_cost numeric(18,6),
 maximum_latency_ms integer,
 minimum_quality_score numeric(8,4),
 conditions jsonb not null default '{}',
 status text not null default 'active' check(status in('active','inactive','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,policy_code)
);

-- 3. Agents, skills, tools and prompts
create table if not exists public.ai_agents(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_code text not null,
 agent_name text not null,
 description text,
 agent_type text not null check(agent_type in('assistant','sales','support','qualification','analysis','research','operations','supervisor','custom')),
 primary_model_id uuid references public.ai_intelligence_models(id) on delete set null,
 routing_policy_id uuid references public.ai_intelligence_routing_policies(id) on delete set null,
 system_prompt text,
 objective text,
 autonomy_level text not null default 'assisted' check(autonomy_level in('manual','assisted','supervised','autonomous')),
 approval_required boolean not null default true,
 maximum_steps integer not null default 20,
 maximum_runtime_seconds integer not null default 300,
 memory_enabled boolean not null default true,
 rag_enabled boolean not null default true,
 tools_enabled boolean not null default true,
 status text not null default 'draft' check(status in('draft','active','paused','inactive','archived')),
 configuration jsonb not null default '{}',
 guardrails jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,agent_code)
);

create table if not exists public.ai_agent_skills(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 skill_code text not null,
 skill_name text not null,
 description text,
 skill_type text not null check(skill_type in('reasoning','classification','extraction','summarization','recommendation','generation','search','tool_use','custom')),
 input_schema jsonb not null default '{}',
 output_schema jsonb not null default '{}',
 implementation_type text not null default 'prompt' check(implementation_type in('prompt','function','workflow','api','custom')),
 implementation_reference text,
 configuration jsonb not null default '{}',
 status text not null default 'active' check(status in('active','inactive','testing','archived')),
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,skill_code)
);

create table if not exists public.ai_agent_skill_assignments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid not null references public.ai_agents(id) on delete cascade,
 skill_id uuid not null references public.ai_agent_skills(id) on delete cascade,
 priority integer not null default 100,
 enabled boolean not null default true,
 configuration jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(agent_id,skill_id)
);

create table if not exists public.ai_tools(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 tool_code text not null,
 tool_name text not null,
 description text,
 tool_type text not null check(tool_type in('database_function','api','workflow','search','calculator','document','communication','custom')),
 implementation_reference text,
 input_schema jsonb not null default '{}',
 output_schema jsonb not null default '{}',
 requires_approval boolean not null default false,
 sensitive boolean not null default false,
 status text not null default 'active' check(status in('active','inactive','testing','archived')),
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,tool_code)
);
create unique index if not exists ai_tools_system_unique_idx on public.ai_tools(tool_code) where organization_id is null;

create table if not exists public.ai_agent_tool_assignments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid not null references public.ai_agents(id) on delete cascade,
 tool_id uuid not null references public.ai_tools(id) on delete cascade,
 allowed boolean not null default true,
 approval_required boolean not null default false,
 conditions jsonb not null default '{}',
 configuration jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(agent_id,tool_id)
);

create table if not exists public.ai_prompt_templates(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 prompt_code text not null,
 prompt_name text not null,
 description text,
 prompt_type text not null check(prompt_type in('system','user','assistant','tool','classification','extraction','summary','rag','custom')),
 task_type text,
 default_model_id uuid references public.ai_intelligence_models(id) on delete set null,
 template_text text not null,
 variables jsonb not null default '[]',
 output_schema jsonb not null default '{}',
 status text not null default 'active' check(status in('draft','active','inactive','archived')),
 is_system_prompt boolean not null default false,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,prompt_code)
);
create unique index if not exists ai_prompts_system_unique_idx on public.ai_prompt_templates(prompt_code) where organization_id is null;

create table if not exists public.ai_prompt_versions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 prompt_template_id uuid not null references public.ai_prompt_templates(id) on delete cascade,
 version_number integer not null,
 template_text text not null,
 variables jsonb not null default '[]',
 output_schema jsonb not null default '{}',
 change_summary text,
 is_current boolean not null default false,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(prompt_template_id,version_number)
);
create unique index if not exists ai_prompt_current_unique_idx on public.ai_prompt_versions(prompt_template_id) where is_current=true;

-- 4. Sessions, messages and memory
create table if not exists public.ai_sessions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid references public.ai_agents(id) on delete set null,
 user_id uuid references auth.users(id) on delete set null,
 session_key text not null unique,
 session_type text not null default 'conversation' check(session_type in('conversation','task','analysis','workflow','background','evaluation')),
 related_entity_type text,
 related_entity_id uuid,
 status text not null default 'active' check(status in('active','paused','completed','failed','cancelled','expired')),
 context_data jsonb not null default '{}',
 session_summary text,
 started_at timestamptz not null default now(),
 last_activity_at timestamptz not null default now(),
 completed_at timestamptz,
 expires_at timestamptz,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.ai_messages(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 session_id uuid not null references public.ai_sessions(id) on delete cascade,
 sequence_number integer not null,
 role text not null check(role in('system','user','assistant','tool')),
 content_text text,
 content_json jsonb,
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 prompt_template_id uuid references public.ai_prompt_templates(id) on delete set null,
 tool_call_id text,
 tool_name text,
 input_tokens integer,
 output_tokens integer,
 cached_tokens integer,
 finish_reason text,
 latency_ms bigint,
 safety_data jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(session_id,sequence_number)
);

create table if not exists public.ai_memory_entries(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid references public.ai_agents(id) on delete set null,
 session_id uuid references public.ai_sessions(id) on delete set null,
 user_id uuid references auth.users(id) on delete set null,
 memory_type text not null check(memory_type in('working','episodic','semantic','procedural','preference','entity','summary')),
 scope_type text not null default 'session' check(scope_type in('session','user','agent','organization','entity')),
 scope_reference text,
 memory_key text,
 memory_text text,
 memory_json jsonb,
 importance_score numeric(8,4) not null default 0.5,
 confidence_score numeric(8,4) not null default 0.5,
 source_type text,
 source_id uuid,
 status text not null default 'active' check(status in('active','superseded','expired','deleted')),
 expires_at timestamptz,
 last_accessed_at timestamptz,
 access_count integer not null default 0,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists ai_memory_scope_idx on public.ai_memory_entries(organization_id,scope_type,scope_reference,status);

-- 5. Knowledge and RAG
create table if not exists public.ai_knowledge_bases(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 knowledge_base_code text not null,
 knowledge_base_name text not null,
 description text,
 knowledge_type text not null default 'general' check(knowledge_type in('general','sales','project','policy','product','support','legal','custom')),
 embedding_model_id uuid references public.ai_intelligence_models(id) on delete set null,
 chunk_size integer not null default 1000,
 chunk_overlap integer not null default 150,
 retrieval_top_k integer not null default 8,
 similarity_threshold numeric(8,4) not null default 0.7,
 status text not null default 'active' check(status in('draft','active','indexing','error','inactive','archived')),
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,knowledge_base_code)
);

create table if not exists public.ai_knowledge_documents(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 knowledge_base_id uuid not null references public.ai_knowledge_bases(id) on delete cascade,
 document_id uuid references public.documents(id) on delete set null,
 document_title text not null,
 source_type text not null check(source_type in('document','url','text','database','api','manual','custom')),
 source_reference text,
 source_checksum text,
 content_text text,
 content_metadata jsonb not null default '{}',
 status text not null default 'pending' check(status in('pending','processing','indexed','failed','archived')),
 indexed_at timestamptz,
 last_error text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.ai_knowledge_chunks(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 knowledge_base_id uuid not null references public.ai_knowledge_bases(id) on delete cascade,
 knowledge_document_id uuid not null references public.ai_knowledge_documents(id) on delete cascade,
 chunk_index integer not null,
 chunk_text text not null,
 token_count integer,
 embedding_reference text,
 embedding_dimensions integer,
 embedding_checksum text,
 section_title text,
 page_number integer,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(knowledge_document_id,chunk_index)
);

create table if not exists public.ai_rag_retrieval_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 session_id uuid references public.ai_sessions(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 knowledge_base_id uuid references public.ai_knowledge_bases(id) on delete set null,
 query_text text not null,
 rewritten_query text,
 status text not null default 'queued' check(status in('queued','running','completed','failed','cancelled')),
 top_k integer not null default 8,
 similarity_threshold numeric(8,4) not null default 0.7,
 retrieval_strategy text not null default 'hybrid' check(retrieval_strategy in('vector','keyword','hybrid','reranked','custom')),
 result_count integer,
 duration_ms bigint,
 error_code text,
 error_message text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 completed_at timestamptz
);

create table if not exists public.ai_rag_retrieval_results(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 retrieval_job_id uuid not null references public.ai_rag_retrieval_jobs(id) on delete cascade,
 knowledge_chunk_id uuid not null references public.ai_knowledge_chunks(id) on delete cascade,
 result_rank integer not null,
 similarity_score numeric(8,6),
 keyword_score numeric(8,6),
 rerank_score numeric(8,6),
 citation_label text,
 selected boolean not null default true,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(retrieval_job_id,result_rank)
);

-- 6. Tasks, actions, decisions and recommendations
create table if not exists public.ai_tasks(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid references public.ai_agents(id) on delete set null,
 session_id uuid references public.ai_sessions(id) on delete set null,
 requested_by uuid references auth.users(id) on delete set null,
 task_type text not null,
 task_name text,
 task_description text,
 related_entity_type text,
 related_entity_id uuid,
 status text not null default 'queued' check(status in('queued','claimed','running','waiting_approval','completed','failed','cancelled','expired')),
 priority integer not null default 100,
 input_data jsonb not null default '{}',
 output_data jsonb not null default '{}',
 scheduled_at timestamptz not null default now(),
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 step_count integer not null default 0,
 error_code text,
 error_message text,
 error_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists ai_tasks_queue_idx on public.ai_tasks(status,scheduled_at,priority,created_at) where status in('queued','failed');

create table if not exists public.ai_task_steps(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 task_id uuid not null references public.ai_tasks(id) on delete cascade,
 step_number integer not null,
 step_type text not null check(step_type in('reasoning','prompt','tool','retrieval','decision','approval','output','custom')),
 step_name text,
 status text not null default 'pending' check(status in('pending','running','completed','failed','skipped','cancelled')),
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 prompt_template_id uuid references public.ai_prompt_templates(id) on delete set null,
 tool_id uuid references public.ai_tools(id) on delete set null,
 input_data jsonb not null default '{}',
 output_data jsonb not null default '{}',
 started_at timestamptz,
 completed_at timestamptz,
 duration_ms bigint,
 input_tokens integer,
 output_tokens integer,
 cost_amount numeric(18,8),
 error_code text,
 error_message text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(task_id,step_number)
);

create table if not exists public.ai_actions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 task_id uuid references public.ai_tasks(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 action_type text not null,
 action_name text,
 description text,
 target_type text,
 target_id uuid,
 tool_id uuid references public.ai_tools(id) on delete set null,
 risk_level text not null default 'low' check(risk_level in('low','medium','high','critical')),
 approval_required boolean not null default false,
 status text not null default 'proposed' check(status in('proposed','waiting_approval','approved','rejected','executing','completed','failed','cancelled')),
 action_payload jsonb not null default '{}',
 execution_result jsonb not null default '{}',
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 rejected_by uuid references auth.users(id) on delete set null,
 rejected_at timestamptz,
 rejection_reason text,
 executed_at timestamptz,
 error_code text,
 error_message text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.ai_decisions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 task_id uuid references public.ai_tasks(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 decision_type text not null,
 decision_subject_type text,
 decision_subject_id uuid,
 decision_value jsonb not null default '{}',
 rationale text,
 confidence_score numeric(8,4),
 risk_score numeric(8,4),
 evidence jsonb not null default '[]',
 alternatives jsonb not null default '[]',
 status text not null default 'proposed' check(status in('proposed','accepted','rejected','overridden','expired')),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 review_notes text,
 created_at timestamptz not null default now()
);

create table if not exists public.ai_recommendations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 agent_id uuid references public.ai_agents(id) on delete set null,
 task_id uuid references public.ai_tasks(id) on delete set null,
 recommendation_type text not null,
 title text not null,
 description text,
 related_entity_type text,
 related_entity_id uuid,
 priority text not null default 'medium' check(priority in('low','medium','high','critical')),
 confidence_score numeric(8,4),
 expected_impact_score numeric(8,4),
 recommendation_data jsonb not null default '{}',
 status text not null default 'open' check(status in('open','accepted','rejected','applied','expired','dismissed')),
 accepted_by uuid references auth.users(id) on delete set null,
 accepted_at timestamptz,
 applied_at timestamptz,
 expires_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.ai_scores(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 score_type text not null,
 entity_type text not null,
 entity_id uuid not null,
 score_value numeric(18,6) not null,
 score_label text,
 confidence_score numeric(8,4),
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 factors jsonb not null default '[]',
 explanation text,
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists ai_scores_entity_idx on public.ai_scores(organization_id,entity_type,entity_id,score_type,created_at desc);

create table if not exists public.ai_summaries(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 summary_type text not null,
 entity_type text not null,
 entity_id uuid not null,
 title text,
 summary_text text not null,
 summary_data jsonb not null default '{}',
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 source_count integer,
 confidence_score numeric(8,4),
 status text not null default 'active' check(status in('active','superseded','expired','archived')),
 generated_at timestamptz not null default now(),
 expires_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now()
);

create table if not exists public.ai_insights(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 insight_type text not null,
 insight_category text,
 title text not null,
 description text not null,
 related_entity_type text,
 related_entity_id uuid,
 severity text not null default 'info' check(severity in('info','low','medium','high','critical')),
 confidence_score numeric(8,4),
 impact_score numeric(8,4),
 evidence jsonb not null default '[]',
 recommended_actions jsonb not null default '[]',
 status text not null default 'open' check(status in('open','acknowledged','resolved','dismissed','expired')),
 acknowledged_by uuid references auth.users(id) on delete set null,
 acknowledged_at timestamptz,
 resolved_at timestamptz,
 expires_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

-- 7. Usage, budgets and evaluations
create table if not exists public.ai_usage_records(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 provider_id uuid references public.ai_intelligence_providers(id) on delete set null,
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 provider_connection_id uuid references public.ai_intelligence_provider_connections(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 session_id uuid references public.ai_sessions(id) on delete set null,
 task_id uuid references public.ai_tasks(id) on delete set null,
 operation_type text not null,
 input_tokens integer not null default 0,
 output_tokens integer not null default 0,
 cached_tokens integer not null default 0,
 total_tokens integer generated always as(input_tokens+output_tokens+cached_tokens) stored,
 input_cost numeric(18,8) not null default 0,
 output_cost numeric(18,8) not null default 0,
 cached_cost numeric(18,8) not null default 0,
 total_cost numeric(18,8) generated always as(input_cost+output_cost+cached_cost) stored,
 currency text not null default 'USD',
 latency_ms bigint,
 success boolean not null default true,
 error_code text,
 error_message text,
 occurred_at timestamptz not null default now(),
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index if not exists ai_usage_time_idx on public.ai_usage_records(organization_id,occurred_at desc);

create table if not exists public.ai_budgets(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 budget_code text not null,
 budget_name text not null,
 period_type text not null check(period_type in('daily','weekly','monthly','quarterly','annual','custom')),
 budget_amount numeric(18,8),
 token_limit bigint,
 request_limit bigint,
 current_cost numeric(18,8) not null default 0,
 current_tokens bigint not null default 0,
 current_requests bigint not null default 0,
 warning_threshold_percentage numeric(8,4) not null default 80,
 hard_limit boolean not null default true,
 period_start timestamptz not null,
 period_end timestamptz not null,
 status text not null default 'active' check(status in('active','warning','exceeded','inactive','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,budget_code,period_start)
);

create table if not exists public.ai_evaluation_datasets(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 dataset_code text not null,
 dataset_name text not null,
 description text,
 task_type text not null,
 status text not null default 'active' check(status in('draft','active','inactive','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,dataset_code)
);

create table if not exists public.ai_evaluation_cases(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 evaluation_dataset_id uuid not null references public.ai_evaluation_datasets(id) on delete cascade,
 case_code text not null,
 input_data jsonb not null default '{}',
 expected_output jsonb not null default '{}',
 scoring_criteria jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(evaluation_dataset_id,case_code)
);

create table if not exists public.ai_evaluation_runs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 evaluation_dataset_id uuid not null references public.ai_evaluation_datasets(id) on delete cascade,
 model_id uuid references public.ai_intelligence_models(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 status text not null default 'queued' check(status in('queued','running','completed','failed','cancelled')),
 started_at timestamptz,
 completed_at timestamptz,
 total_cases integer not null default 0,
 passed_cases integer not null default 0,
 failed_cases integer not null default 0,
 average_score numeric(8,4),
 total_cost numeric(18,8),
 average_latency_ms bigint,
 summary_data jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists public.ai_evaluation_results(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 evaluation_run_id uuid not null references public.ai_evaluation_runs(id) on delete cascade,
 evaluation_case_id uuid not null references public.ai_evaluation_cases(id) on delete cascade,
 actual_output jsonb not null default '{}',
 score numeric(8,4),
 passed boolean,
 evaluator_type text not null default 'rule' check(evaluator_type in('rule','llm','human','hybrid')),
 evaluator_notes text,
 latency_ms bigint,
 cost_amount numeric(18,8),
 created_at timestamptz not null default now(),
 unique(evaluation_run_id,evaluation_case_id)
);

-- 8. Event outbox and logs
create table if not exists public.ai_intelligence_event_outbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 agent_id uuid references public.ai_agents(id) on delete set null,
 task_id uuid references public.ai_tasks(id) on delete set null,
 event_name text not null,
 destination text not null default 'internal' check(destination in('internal','automation_engine','workflow_engine','notification_engine','communication_engine','integration_api','n8n','analytics','audit')),
 source_type text,
 source_id uuid,
 status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
 priority integer not null default 100,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 payload jsonb not null default '{}',
 available_at timestamptz not null default now(),
 delivery_attempts integer not null default 0,
 maximum_attempts integer not null default 10,
 delivered_at timestamptz,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists ai_event_idempotency_idx on public.ai_intelligence_event_outbox(organization_id,idempotency_key) where idempotency_key is not null;

create table if not exists public.ai_intelligence_logs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
 agent_id uuid references public.ai_agents(id) on delete set null,
 session_id uuid references public.ai_sessions(id) on delete set null,
 task_id uuid references public.ai_tasks(id) on delete set null,
 log_level text not null default 'info' check(log_level in('debug','info','warning','error','critical')),
 event_name text,
 message text,
 error_code text,
 error_message text,
 log_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now()
);

-- 9. Updated-at triggers
do $$
declare t text;
begin
 foreach t in array array[
 'ai_intelligence_providers','ai_intelligence_provider_connections','ai_intelligence_models',
 'ai_intelligence_routing_policies','ai_agents','ai_agent_skills','ai_tools',
 'ai_prompt_templates','ai_sessions','ai_memory_entries','ai_knowledge_bases',
 'ai_knowledge_documents','ai_tasks','ai_actions','ai_recommendations','ai_insights',
 'ai_budgets','ai_evaluation_datasets','ai_intelligence_event_outbox'
 ] loop
  execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
  execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end;
$$;

-- 10. Core functions
create or replace function public.create_ai_intelligence_agent(
 requested_organization_id uuid, requested_agent_code text, requested_agent_name text,
 requested_agent_type text, requested_primary_model_id uuid default null,
 requested_description text default null, requested_system_prompt text default null,
 requested_objective text default null, requested_autonomy_level text default 'assisted',
 requested_approval_required boolean default true,
 requested_configuration jsonb default '{}'::jsonb,
 requested_guardrails jsonb default '{}'::jsonb,
 requested_metadata jsonb default '{}'::jsonb
) returns public.ai_agents
language plpgsql security definer set search_path=''
as $$
declare r public.ai_agents;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'ai_intelligence.manage_agents') then raise exception 'Permission denied'; end if;
 insert into public.ai_agents(organization_id,agent_code,agent_name,description,agent_type,primary_model_id,system_prompt,objective,autonomy_level,approval_required,status,configuration,guardrails,metadata,created_by,updated_by)
 values(requested_organization_id,requested_agent_code,requested_agent_name,requested_description,requested_agent_type,requested_primary_model_id,requested_system_prompt,requested_objective,requested_autonomy_level,requested_approval_required,'active',coalesce(requested_configuration,'{}'),coalesce(requested_guardrails,'{}'),coalesce(requested_metadata,'{}'),auth.uid(),auth.uid())
 on conflict(organization_id,agent_code) do update set agent_name=excluded.agent_name,description=excluded.description,agent_type=excluded.agent_type,primary_model_id=excluded.primary_model_id,system_prompt=excluded.system_prompt,objective=excluded.objective,autonomy_level=excluded.autonomy_level,approval_required=excluded.approval_required,configuration=excluded.configuration,guardrails=excluded.guardrails,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end;
$$;

create or replace function public.create_ai_intelligence_session(
 requested_organization_id uuid, requested_agent_id uuid default null,
 requested_session_type text default 'conversation', requested_related_entity_type text default null,
 requested_related_entity_id uuid default null, requested_context_data jsonb default '{}'::jsonb,
 requested_expires_at timestamptz default null, requested_correlation_id text default null,
 requested_trace_id text default null, requested_metadata jsonb default '{}'::jsonb
) returns public.ai_sessions
language plpgsql security definer set search_path=''
as $$
declare r public.ai_sessions;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'ai_intelligence.execute') then raise exception 'Permission denied'; end if;
 insert into public.ai_sessions(organization_id,agent_id,user_id,session_key,session_type,related_entity_type,related_entity_id,status,context_data,expires_at,correlation_id,trace_id,metadata)
 values(requested_organization_id,requested_agent_id,auth.uid(),'AIS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),requested_session_type,requested_related_entity_type,requested_related_entity_id,'active',coalesce(requested_context_data,'{}'),requested_expires_at,requested_correlation_id,requested_trace_id,coalesce(requested_metadata,'{}')) returning * into r;
 return r;
end;
$$;

create or replace function public.append_ai_message(
 requested_session_id uuid, requested_role text, requested_content_text text default null,
 requested_content_json jsonb default null, requested_model_id uuid default null,
 requested_prompt_template_id uuid default null, requested_tool_call_id text default null,
 requested_tool_name text default null, requested_input_tokens integer default null,
 requested_output_tokens integer default null, requested_cached_tokens integer default null,
 requested_finish_reason text default null, requested_latency_ms bigint default null,
 requested_metadata jsonb default '{}'::jsonb
) returns public.ai_messages
language plpgsql security definer set search_path=''
as $$
declare s public.ai_sessions; n integer; r public.ai_messages;
begin
 select * into s from public.ai_sessions where id=requested_session_id for update;
 if not found then raise exception 'AI session not found'; end if;
 if auth.role()<>'service_role' and auth.uid() is distinct from s.user_id and not public.has_organization_permission(s.organization_id,'ai_intelligence.execute') then raise exception 'Permission denied'; end if;
 select coalesce(max(sequence_number),0)+1 into n from public.ai_messages where session_id=requested_session_id;
 insert into public.ai_messages(organization_id,session_id,sequence_number,role,content_text,content_json,model_id,prompt_template_id,tool_call_id,tool_name,input_tokens,output_tokens,cached_tokens,finish_reason,latency_ms,metadata)
 values(s.organization_id,s.id,n,requested_role,requested_content_text,requested_content_json,requested_model_id,requested_prompt_template_id,requested_tool_call_id,requested_tool_name,requested_input_tokens,requested_output_tokens,requested_cached_tokens,requested_finish_reason,requested_latency_ms,coalesce(requested_metadata,'{}')) returning * into r;
 update public.ai_sessions set last_activity_at=now(),updated_at=now() where id=s.id;
 return r;
end;
$$;

create or replace function public.upsert_ai_memory(
 requested_organization_id uuid, requested_memory_type text, requested_scope_type text,
 requested_scope_reference text, requested_memory_key text, requested_memory_text text default null,
 requested_memory_json jsonb default null, requested_agent_id uuid default null,
 requested_session_id uuid default null, requested_user_id uuid default null,
 requested_importance_score numeric default 0.5, requested_confidence_score numeric default 0.5,
 requested_expires_at timestamptz default null, requested_metadata jsonb default '{}'::jsonb
) returns public.ai_memory_entries
language plpgsql security definer set search_path=''
as $$
declare r public.ai_memory_entries;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'ai_intelligence.manage_memory') then raise exception 'Permission denied'; end if;
 update public.ai_memory_entries set status='superseded',updated_at=now() where organization_id=requested_organization_id and scope_type=requested_scope_type and scope_reference is not distinct from requested_scope_reference and memory_key is not distinct from requested_memory_key and status='active';
 insert into public.ai_memory_entries(organization_id,agent_id,session_id,user_id,memory_type,scope_type,scope_reference,memory_key,memory_text,memory_json,importance_score,confidence_score,status,expires_at,metadata)
 values(requested_organization_id,requested_agent_id,requested_session_id,requested_user_id,requested_memory_type,requested_scope_type,requested_scope_reference,requested_memory_key,requested_memory_text,requested_memory_json,requested_importance_score,requested_confidence_score,'active',requested_expires_at,coalesce(requested_metadata,'{}')) returning * into r;
 return r;
end;
$$;

create or replace function public.create_ai_task(
 requested_organization_id uuid, requested_task_type text, requested_agent_id uuid default null,
 requested_session_id uuid default null, requested_task_name text default null,
 requested_task_description text default null, requested_related_entity_type text default null,
 requested_related_entity_id uuid default null, requested_input_data jsonb default '{}'::jsonb,
 requested_priority integer default 100, requested_scheduled_at timestamptz default now(),
 requested_correlation_id text default null, requested_trace_id text default null,
 requested_metadata jsonb default '{}'::jsonb
) returns public.ai_tasks
language plpgsql security definer set search_path=''
as $$
declare r public.ai_tasks;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'ai_intelligence.execute') then raise exception 'Permission denied'; end if;
 insert into public.ai_tasks(organization_id,agent_id,session_id,requested_by,task_type,task_name,task_description,related_entity_type,related_entity_id,status,priority,input_data,scheduled_at,correlation_id,trace_id,metadata)
 values(requested_organization_id,requested_agent_id,requested_session_id,auth.uid(),requested_task_type,requested_task_name,requested_task_description,requested_related_entity_type,requested_related_entity_id,'queued',requested_priority,coalesce(requested_input_data,'{}'),coalesce(requested_scheduled_at,now()),requested_correlation_id,requested_trace_id,coalesce(requested_metadata,'{}')) returning * into r;
 return r;
end;
$$;

create or replace function public.claim_ai_task(requested_worker_id text,requested_organization_id uuid default null,requested_lock_seconds integer default 600)
returns public.ai_tasks language plpgsql security definer set search_path=''
as $$
declare r public.ai_tasks;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim AI tasks'; end if;
 select * into r from public.ai_tasks t where t.status in('queued','failed') and t.scheduled_at<=now() and(requested_organization_id is null or t.organization_id=requested_organization_id) order by t.priority,t.scheduled_at,t.created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.ai_tasks set status='claimed',claimed_at=now(),claimed_by=requested_worker_id,lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now() where id=r.id returning * into r;
 return r;
end;
$$;

create or replace function public.complete_ai_task(requested_task_id uuid,requested_lock_token text,requested_output_data jsonb default '{}'::jsonb,requested_step_count integer default 0)
returns public.ai_tasks language plpgsql security definer set search_path=''
as $$
declare r public.ai_tasks;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete AI tasks'; end if;
 select * into r from public.ai_tasks where id=requested_task_id for update;
 if not found then raise exception 'AI task not found'; end if;
 if r.lock_token is distinct from requested_lock_token then raise exception 'Invalid AI task lock token'; end if;
 update public.ai_tasks set status='completed',output_data=coalesce(requested_output_data,'{}'),step_count=requested_step_count,completed_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now() where id=requested_task_id returning * into r;
 return r;
end;
$$;

create or replace function public.approve_ai_action(requested_action_id uuid,requested_approved boolean,requested_notes text default null)
returns public.ai_actions language plpgsql security definer set search_path=''
as $$
declare r public.ai_actions;
begin
 select * into r from public.ai_actions where id=requested_action_id for update;
 if not found then raise exception 'AI action not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(r.organization_id,'ai_intelligence.approve_actions') then raise exception 'Permission denied'; end if;
 update public.ai_actions set status=case when requested_approved then 'approved' else 'rejected' end,approved_by=case when requested_approved then auth.uid() else approved_by end,approved_at=case when requested_approved then now() else approved_at end,rejected_by=case when requested_approved then rejected_by else auth.uid() end,rejected_at=case when requested_approved then rejected_at else now() end,rejection_reason=case when requested_approved then rejection_reason else requested_notes end,metadata=metadata||jsonb_build_object('review_notes',requested_notes),updated_at=now() where id=requested_action_id returning * into r;
 return r;
end;
$$;

create or replace function public.record_ai_usage(
 requested_organization_id uuid, requested_model_id uuid, requested_operation_type text,
 requested_input_tokens integer default 0, requested_output_tokens integer default 0,
 requested_cached_tokens integer default 0, requested_agent_id uuid default null,
 requested_session_id uuid default null, requested_task_id uuid default null,
 requested_latency_ms bigint default null, requested_success boolean default true,
 requested_error_code text default null, requested_error_message text default null,
 requested_metadata jsonb default '{}'::jsonb
) returns public.ai_usage_records
language plpgsql security definer set search_path=''
as $$
declare m public.ai_intelligence_models; r public.ai_usage_records; ic numeric(18,8); oc numeric(18,8); cc numeric(18,8);
begin
 select * into m from public.ai_intelligence_models where id=requested_model_id;
 if not found then raise exception 'AI model not found'; end if;
 ic:=round(coalesce(requested_input_tokens,0)*coalesce(m.input_cost_per_million,0)/1000000,8);
 oc:=round(coalesce(requested_output_tokens,0)*coalesce(m.output_cost_per_million,0)/1000000,8);
 cc:=round(coalesce(requested_cached_tokens,0)*coalesce(m.cached_input_cost_per_million,0)/1000000,8);
 insert into public.ai_usage_records(organization_id,provider_id,model_id,provider_connection_id,agent_id,session_id,task_id,operation_type,input_tokens,output_tokens,cached_tokens,input_cost,output_cost,cached_cost,latency_ms,success,error_code,error_message,metadata)
 values(requested_organization_id,m.provider_id,m.id,m.provider_connection_id,requested_agent_id,requested_session_id,requested_task_id,requested_operation_type,coalesce(requested_input_tokens,0),coalesce(requested_output_tokens,0),coalesce(requested_cached_tokens,0),ic,oc,cc,requested_latency_ms,requested_success,requested_error_code,requested_error_message,coalesce(requested_metadata,'{}')) returning * into r;
 update public.ai_budgets set current_cost=current_cost+r.total_cost,current_tokens=current_tokens+r.total_tokens,current_requests=current_requests+1,status=case when hard_limit and budget_amount is not null and current_cost+r.total_cost>=budget_amount then 'exceeded' when budget_amount is not null and current_cost+r.total_cost>=budget_amount*warning_threshold_percentage/100 then 'warning' else status end,updated_at=now() where organization_id=requested_organization_id and status in('active','warning') and now() between period_start and period_end;
 return r;
end;
$$;

create or replace function public.publish_ai_intelligence_event(
 requested_organization_id uuid, requested_event_name text, requested_payload jsonb default '{}'::jsonb,
 requested_destination text default 'internal', requested_agent_id uuid default null,
 requested_task_id uuid default null, requested_source_type text default null,
 requested_source_id uuid default null, requested_priority integer default 100,
 requested_idempotency_key text default null, requested_correlation_id text default null,
 requested_trace_id text default null, requested_available_at timestamptz default now()
) returns public.ai_intelligence_event_outbox
language plpgsql security definer set search_path=''
as $$
declare e public.ai_intelligence_event_outbox; r public.ai_intelligence_event_outbox;
begin
 if requested_idempotency_key is not null then select * into e from public.ai_intelligence_event_outbox where organization_id is not distinct from requested_organization_id and idempotency_key=requested_idempotency_key limit 1; if found then return e; end if; end if;
 insert into public.ai_intelligence_event_outbox(organization_id,agent_id,task_id,event_name,destination,source_type,source_id,status,priority,idempotency_key,correlation_id,trace_id,payload,available_at)
 values(requested_organization_id,requested_agent_id,requested_task_id,requested_event_name,requested_destination,requested_source_type,requested_source_id,'pending',requested_priority,requested_idempotency_key,requested_correlation_id,requested_trace_id,coalesce(requested_payload,'{}'),coalesce(requested_available_at,now())) returning * into r;
 return r;
end;
$$;

-- Function grants
revoke all on function public.create_ai_intelligence_agent(uuid,text,text,text,uuid,text,text,text,text,boolean,jsonb,jsonb,jsonb) from public;
grant execute on function public.create_ai_intelligence_agent(uuid,text,text,text,uuid,text,text,text,text,boolean,jsonb,jsonb,jsonb) to authenticated,service_role;
revoke all on function public.create_ai_intelligence_session(uuid,uuid,text,text,uuid,jsonb,timestamptz,text,text,jsonb) from public;
grant execute on function public.create_ai_intelligence_session(uuid,uuid,text,text,uuid,jsonb,timestamptz,text,text,jsonb) to authenticated,service_role;
revoke all on function public.append_ai_message(uuid,text,text,jsonb,uuid,uuid,text,text,integer,integer,integer,text,bigint,jsonb) from public;
grant execute on function public.append_ai_message(uuid,text,text,jsonb,uuid,uuid,text,text,integer,integer,integer,text,bigint,jsonb) to authenticated,service_role;
revoke all on function public.upsert_ai_memory(uuid,text,text,text,text,text,jsonb,uuid,uuid,uuid,numeric,numeric,timestamptz,jsonb) from public;
grant execute on function public.upsert_ai_memory(uuid,text,text,text,text,text,jsonb,uuid,uuid,uuid,numeric,numeric,timestamptz,jsonb) to authenticated,service_role;
revoke all on function public.create_ai_task(uuid,text,uuid,uuid,text,text,text,uuid,jsonb,integer,timestamptz,text,text,jsonb) from public;
grant execute on function public.create_ai_task(uuid,text,uuid,uuid,text,text,text,uuid,jsonb,integer,timestamptz,text,text,jsonb) to authenticated,service_role;
revoke all on function public.claim_ai_task(text,uuid,integer) from public;
grant execute on function public.claim_ai_task(text,uuid,integer) to service_role;
revoke all on function public.complete_ai_task(uuid,text,jsonb,integer) from public;
grant execute on function public.complete_ai_task(uuid,text,jsonb,integer) to service_role;
revoke all on function public.approve_ai_action(uuid,boolean,text) from public;
grant execute on function public.approve_ai_action(uuid,boolean,text) to authenticated,service_role;
revoke all on function public.record_ai_usage(uuid,uuid,text,integer,integer,integer,uuid,uuid,uuid,bigint,boolean,text,text,jsonb) from public;
grant execute on function public.record_ai_usage(uuid,uuid,text,integer,integer,integer,uuid,uuid,uuid,bigint,boolean,text,text,jsonb) to authenticated,service_role;
revoke all on function public.publish_ai_intelligence_event(uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz) from public;
grant execute on function public.publish_ai_intelligence_event(uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz) to authenticated,service_role;

-- 11. Task events
create or replace function public.emit_ai_task_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
 perform public.publish_ai_intelligence_event(new.organization_id,'ai.task.'||new.status,jsonb_build_object('task_id',new.id,'agent_id',new.agent_id,'task_type',new.task_type,'status',new.status,'related_entity_type',new.related_entity_type,'related_entity_id',new.related_entity_id,'error_code',new.error_code,'error_message',new.error_message),case when new.status in('failed','waiting_approval') then 'notification_engine' else 'analytics' end,new.agent_id,new.id,'ai_task',new.id,case when new.status='failed' then 10 else 50 end,'ai-task:'||new.id::text||':'||new.status,coalesce(new.correlation_id,new.id::text),new.trace_id,now());
 return new;
end;
$$;
drop trigger if exists ai_tasks_emit_events on public.ai_tasks;
create trigger ai_tasks_emit_events after insert or update on public.ai_tasks for each row execute function public.emit_ai_task_events();

-- 12. Analytics views
create or replace view public.ai_intelligence_usage_dashboard with(security_invoker=true) as
select organization_id,model_id,operation_type,count(*) request_count,coalesce(sum(input_tokens),0) input_tokens,coalesce(sum(output_tokens),0) output_tokens,coalesce(sum(cached_tokens),0) cached_tokens,coalesce(sum(total_tokens),0) total_tokens,coalesce(sum(total_cost),0) total_cost,round(avg(latency_ms),2) average_latency_ms,round(count(*) filter(where success)::numeric/nullif(count(*),0)*100,2) success_rate,max(occurred_at) latest_usage_at
from public.ai_usage_records group by organization_id,model_id,operation_type;

create or replace view public.ai_agent_performance_dashboard with(security_invoker=true) as
select a.organization_id,a.id agent_id,a.agent_code,a.agent_name,a.agent_type,count(distinct t.id) task_count,count(distinct t.id) filter(where t.status='completed') completed_tasks,count(distinct t.id) filter(where t.status='failed') failed_tasks,round(count(distinct t.id) filter(where t.status='completed')::numeric/nullif(count(distinct t.id),0)*100,2) completion_rate,coalesce(sum(u.total_cost),0) total_cost,coalesce(sum(u.total_tokens),0) total_tokens,max(t.completed_at) latest_completion_at
from public.ai_agents a left join public.ai_tasks t on t.agent_id=a.id left join public.ai_usage_records u on u.agent_id=a.id
group by a.organization_id,a.id,a.agent_code,a.agent_name,a.agent_type;

create or replace view public.ai_knowledge_dashboard with(security_invoker=true) as
select kb.organization_id,kb.id knowledge_base_id,kb.knowledge_base_code,kb.knowledge_base_name,kb.status,count(distinct d.id) document_count,count(c.id) chunk_count,count(distinct d.id) filter(where d.status='indexed') indexed_documents,count(distinct d.id) filter(where d.status='failed') failed_documents,max(d.indexed_at) latest_indexed_at
from public.ai_knowledge_bases kb left join public.ai_knowledge_documents d on d.knowledge_base_id=kb.id left join public.ai_knowledge_chunks c on c.knowledge_document_id=d.id
group by kb.organization_id,kb.id,kb.knowledge_base_code,kb.knowledge_base_name,kb.status;

create or replace view public.ai_recommendation_dashboard with(security_invoker=true) as
select organization_id,recommendation_type,priority,status,count(*) recommendation_count,round(avg(confidence_score),4) average_confidence,round(avg(expected_impact_score),4) average_impact,max(created_at) latest_created_at,max(applied_at) latest_applied_at
from public.ai_recommendations group by organization_id,recommendation_type,priority,status;

grant select on public.ai_intelligence_usage_dashboard,public.ai_agent_performance_dashboard,public.ai_knowledge_dashboard,public.ai_recommendation_dashboard to authenticated,service_role;

-- 13. Health check
create or replace function public.get_ai_intelligence_engine_health(requested_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.role()<>'service_role' and(requested_organization_id is null or not public.has_organization_permission(requested_organization_id,'ai_intelligence.view_logs')) then raise exception 'Permission denied'; end if;
 return jsonb_build_object(
 'organization_id',requested_organization_id,'checked_at',now(),
 'active_agents',(select count(*) from public.ai_agents a where a.status='active' and(requested_organization_id is null or a.organization_id=requested_organization_id)),
 'active_models',(select count(*) from public.ai_intelligence_models m where m.status='active' and(requested_organization_id is null or m.organization_id=requested_organization_id or m.organization_id is null)),
 'unhealthy_provider_connections',(select count(*) from public.ai_intelligence_provider_connections c where c.health_status in('degraded','unhealthy') and(requested_organization_id is null or c.organization_id=requested_organization_id)),
 'queued_tasks',(select count(*) from public.ai_tasks t where t.status in('queued','claimed','running','failed') and(requested_organization_id is null or t.organization_id=requested_organization_id)),
 'waiting_approval_actions',(select count(*) from public.ai_actions a where a.status='waiting_approval' and(requested_organization_id is null or a.organization_id=requested_organization_id)),
 'knowledge_documents_failed',(select count(*) from public.ai_knowledge_documents d where d.status='failed' and(requested_organization_id is null or d.organization_id=requested_organization_id)),
 'budget_warnings',(select count(*) from public.ai_budgets b where b.status in('warning','exceeded') and(requested_organization_id is null or b.organization_id=requested_organization_id)),
 'pending_outbox_events',(select count(*) from public.ai_intelligence_event_outbox e where e.status in('pending','failed') and(requested_organization_id is null or e.organization_id=requested_organization_id))
 );
end;
$$;
revoke all on function public.get_ai_intelligence_engine_health(uuid) from public;
grant execute on function public.get_ai_intelligence_engine_health(uuid) to authenticated,service_role;

-- 14. RLS
alter table public.ai_intelligence_providers enable row level security;
alter table public.ai_intelligence_provider_connections enable row level security;
alter table public.ai_intelligence_models enable row level security;
alter table public.ai_intelligence_routing_policies enable row level security;
alter table public.ai_agents enable row level security;
alter table public.ai_agent_skills enable row level security;
alter table public.ai_agent_skill_assignments enable row level security;
alter table public.ai_tools enable row level security;
alter table public.ai_agent_tool_assignments enable row level security;
alter table public.ai_prompt_templates enable row level security;
alter table public.ai_prompt_versions enable row level security;
alter table public.ai_sessions enable row level security;
alter table public.ai_messages enable row level security;
alter table public.ai_memory_entries enable row level security;
alter table public.ai_knowledge_bases enable row level security;
alter table public.ai_knowledge_documents enable row level security;
alter table public.ai_knowledge_chunks enable row level security;
alter table public.ai_rag_retrieval_jobs enable row level security;
alter table public.ai_rag_retrieval_results enable row level security;
alter table public.ai_tasks enable row level security;
alter table public.ai_task_steps enable row level security;
alter table public.ai_actions enable row level security;
alter table public.ai_decisions enable row level security;
alter table public.ai_recommendations enable row level security;
alter table public.ai_scores enable row level security;
alter table public.ai_summaries enable row level security;
alter table public.ai_insights enable row level security;
alter table public.ai_usage_records enable row level security;
alter table public.ai_budgets enable row level security;
alter table public.ai_evaluation_datasets enable row level security;
alter table public.ai_evaluation_cases enable row level security;
alter table public.ai_evaluation_runs enable row level security;
alter table public.ai_evaluation_results enable row level security;
alter table public.ai_intelligence_event_outbox enable row level security;
alter table public.ai_intelligence_logs enable row level security;

drop policy if exists ai_providers_select_policy on public.ai_intelligence_providers;
create policy ai_providers_select_policy on public.ai_intelligence_providers for select to authenticated using(true);
drop policy if exists ai_providers_service_policy on public.ai_intelligence_providers;
create policy ai_providers_service_policy on public.ai_intelligence_providers for all to service_role using(true) with check(true);

drop policy if exists ai_models_select_policy on public.ai_intelligence_models;
create policy ai_models_select_policy on public.ai_intelligence_models for select to authenticated using(organization_id is null or public.has_organization_permission(organization_id,'ai_intelligence.view') or public.has_organization_permission(organization_id,'ai_intelligence.view_all'));
drop policy if exists ai_models_service_policy on public.ai_intelligence_models;
create policy ai_models_service_policy on public.ai_intelligence_models for all to service_role using(true) with check(true);

drop policy if exists ai_tools_select_policy on public.ai_tools;
create policy ai_tools_select_policy on public.ai_tools for select to authenticated using(organization_id is null or public.has_organization_permission(organization_id,'ai_intelligence.view') or public.has_organization_permission(organization_id,'ai_intelligence.view_all'));
drop policy if exists ai_tools_service_policy on public.ai_tools;
create policy ai_tools_service_policy on public.ai_tools for all to service_role using(true) with check(true);

drop policy if exists ai_prompts_select_policy on public.ai_prompt_templates;
create policy ai_prompts_select_policy on public.ai_prompt_templates for select to authenticated using(organization_id is null or public.has_organization_permission(organization_id,'ai_intelligence.view') or public.has_organization_permission(organization_id,'ai_intelligence.view_all'));
drop policy if exists ai_prompts_service_policy on public.ai_prompt_templates;
create policy ai_prompts_service_policy on public.ai_prompt_templates for all to service_role using(true) with check(true);

do $$
declare t text;
begin
 foreach t in array array[
 'ai_intelligence_provider_connections','ai_intelligence_routing_policies','ai_agents','ai_agent_skills','ai_agent_skill_assignments','ai_agent_tool_assignments','ai_sessions','ai_messages','ai_memory_entries','ai_knowledge_bases','ai_knowledge_documents','ai_knowledge_chunks','ai_rag_retrieval_jobs','ai_rag_retrieval_results','ai_tasks','ai_task_steps','ai_actions','ai_decisions','ai_recommendations','ai_scores','ai_summaries','ai_insights','ai_usage_records','ai_budgets','ai_evaluation_datasets','ai_evaluation_cases','ai_evaluation_runs','ai_evaluation_results','ai_intelligence_event_outbox','ai_intelligence_logs'
 ] loop
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(public.has_organization_permission(organization_id,''ai_intelligence.view'') or public.has_organization_permission(organization_id,''ai_intelligence.view_all''))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
end;
$$;

drop policy if exists ai_agents_write_policy on public.ai_agents;
create policy ai_agents_write_policy on public.ai_agents for all to authenticated using(public.has_organization_permission(organization_id,'ai_intelligence.manage_agents')) with check(public.has_organization_permission(organization_id,'ai_intelligence.manage_agents'));
drop policy if exists ai_tasks_write_policy on public.ai_tasks;
create policy ai_tasks_write_policy on public.ai_tasks for all to authenticated using(public.has_organization_permission(organization_id,'ai_intelligence.execute')) with check(public.has_organization_permission(organization_id,'ai_intelligence.execute'));

-- 15. Grants
grant select on
 public.ai_intelligence_providers,public.ai_intelligence_provider_connections,public.ai_intelligence_models,
 public.ai_intelligence_routing_policies,public.ai_agents,public.ai_agent_skills,
 public.ai_agent_skill_assignments,public.ai_tools,public.ai_agent_tool_assignments,
 public.ai_prompt_templates,public.ai_prompt_versions,public.ai_sessions,public.ai_messages,
 public.ai_memory_entries,public.ai_knowledge_bases,public.ai_knowledge_documents,
 public.ai_knowledge_chunks,public.ai_rag_retrieval_jobs,public.ai_rag_retrieval_results,
 public.ai_tasks,public.ai_task_steps,public.ai_actions,public.ai_decisions,
 public.ai_recommendations,public.ai_scores,public.ai_summaries,public.ai_insights,
 public.ai_usage_records,public.ai_budgets,public.ai_evaluation_datasets,
 public.ai_evaluation_cases,public.ai_evaluation_runs,public.ai_evaluation_results,
 public.ai_intelligence_event_outbox,public.ai_intelligence_logs
 to authenticated;

grant all on
 public.ai_intelligence_providers,public.ai_intelligence_provider_connections,public.ai_intelligence_models,
 public.ai_intelligence_routing_policies,public.ai_agents,public.ai_agent_skills,
 public.ai_agent_skill_assignments,public.ai_tools,public.ai_agent_tool_assignments,
 public.ai_prompt_templates,public.ai_prompt_versions,public.ai_sessions,public.ai_messages,
 public.ai_memory_entries,public.ai_knowledge_bases,public.ai_knowledge_documents,
 public.ai_knowledge_chunks,public.ai_rag_retrieval_jobs,public.ai_rag_retrieval_results,
 public.ai_tasks,public.ai_task_steps,public.ai_actions,public.ai_decisions,
 public.ai_recommendations,public.ai_scores,public.ai_summaries,public.ai_insights,
 public.ai_usage_records,public.ai_budgets,public.ai_evaluation_datasets,
 public.ai_evaluation_cases,public.ai_evaluation_runs,public.ai_evaluation_results,
 public.ai_intelligence_event_outbox,public.ai_intelligence_logs
 to service_role;

-- 16. Final validation
do $$
declare item text; missing_items text[]:='{}';
begin
 foreach item in array array[
 'ai_intelligence_providers','ai_intelligence_provider_connections','ai_intelligence_models','ai_intelligence_routing_policies','ai_agents','ai_agent_skills','ai_agent_skill_assignments','ai_tools','ai_agent_tool_assignments','ai_prompt_templates','ai_prompt_versions','ai_sessions','ai_messages','ai_memory_entries','ai_knowledge_bases','ai_knowledge_documents','ai_knowledge_chunks','ai_rag_retrieval_jobs','ai_rag_retrieval_results','ai_tasks','ai_task_steps','ai_actions','ai_decisions','ai_recommendations','ai_scores','ai_summaries','ai_insights','ai_usage_records','ai_budgets','ai_evaluation_datasets','ai_evaluation_cases','ai_evaluation_runs','ai_evaluation_results','ai_intelligence_event_outbox','ai_intelligence_logs'
 ] loop
  if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then missing_items:=array_append(missing_items,'table:'||item); end if;
 end loop;
 foreach item in array array[
 'create_ai_intelligence_agent','create_ai_intelligence_session','append_ai_message','upsert_ai_memory','create_ai_task','claim_ai_task','complete_ai_task','approve_ai_action','record_ai_usage','publish_ai_intelligence_event','get_ai_intelligence_engine_health'
 ] loop
  if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then missing_items:=array_append(missing_items,'function:'||item); end if;
 end loop;
 if cardinality(missing_items)>0 then raise exception '025 migration validation failed. Missing: %',array_to_string(missing_items,', '); end if;
end;
$$;

insert into public.ai_intelligence_logs(organization_id,log_level,event_name,message,log_data)
select o.id,'info','migration.025.completed','AI Intelligence Engine migration 025 completed',jsonb_build_object('migration','025_ai_intelligence_engine','completed_at',now(),'modules',jsonb_build_array('providers','models','routing','agents','skills','tools','prompts','sessions','messages','memory','knowledge','rag','tasks','actions','decisions','recommendations','scores','summaries','insights','usage','budgets','evaluation','analytics','event_outbox'))
from public.organizations o
where not exists(select 1 from public.ai_intelligence_logs l where l.organization_id=o.id and l.event_name='migration.025.completed');

commit;