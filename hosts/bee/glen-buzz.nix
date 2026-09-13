# ── glen channel plugins (buzz identities) ────────────────────────────
# The @glen/channel-buzz plugin (source of truth: the deployed copy at
# /var/lib/dsh/profiles/glen/node_modules/@glen/channel-buzz, edited in
# place — the ~/glen staging repo was retired 2026-09-13) bridges the
# self-hosted nostr relay (buzz.internal.crussell.io) into dsh sessions.
# This module only provides the secrets (agenix, never in patch files).
{
  # per-persona nostr identities (glen/gloo) — env-file format
  # GLEN_BUZZ_NSEC_<PERSONA>=<hex>, consumed by @glen/channel-buzz
  age.secrets.glen-buzz-nsecs = {
    file = ../../secrets/glen-buzz-nsecs.age;
    mode = "0440";
    group = "users";
  };
}
