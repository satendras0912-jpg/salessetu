-- Run only after 036_Platform_Integration_Validation_Engine_v7.sql succeeds.
notify pgrst, 'reload schema';

select
  'PostgREST schema reload requested'::text as status,
  now() as requested_at;
