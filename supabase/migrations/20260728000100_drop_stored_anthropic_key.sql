-- Stop storing users' Anthropic API keys in Postgres. DESTRUCTIVE — read the
-- ordering below before running.
--
-- An Anthropic key is spendable money. It was written to
-- user_settings.anthropic_api_key in plain text and read back to the client on
-- every Settings load. From the app build that ships alongside this migration
-- the key lives only in the device Keychain (see AnthropicKeyStore.swift) and
-- reaches the API as an X-Anthropic-Key request header, so it is never at rest
-- on our infrastructure and a database breach exposes no keys.
--
-- ORDER OF OPERATIONS. This migration drops the only copy of every stored key,
-- so it goes last:
--
--   1. Deploy the web app change: read the key from the X-Anthropic-Key header
--      instead of this column, stop writing the column, and make sure the
--      header is excluded from request logging.
--   2. Ship the iOS build containing AnthropicKeyStore.
--   3. Tell existing BYOK users to revoke their key at console.anthropic.com
--      and paste a fresh one into the app. A key that sat in plain text has to
--      be treated as burned — you cannot un-leak it, and this step is the only
--      thing that actually makes them safe.
--   4. Run this migration.
--
-- Between steps 1 and 4 the column simply sits unused, so there is no rush.

begin;

alter table public.user_settings
  drop column if exists anthropic_api_key;

commit;
