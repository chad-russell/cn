# ── glen channel plugins (buzz identities) ────────────────────────────
# The @glen/channel-buzz plugin (source of truth: ~/glen repo,
# plugins/channel-buzz) bridges the self-hosted nostr relay
# (buzz.internal.crussell.io) into dsh sessions. Deployed into the glen
# profile's node_modules by the glen repo's sync flow — this module only
# provides the secrets (agenix, never in patch files or the repo).
{
  # per-persona nostr identities (glen/gloo) — env-file format
  # GLEN_BUZZ_NSEC_<PERSONA>=<hex>, consumed by @glen/channel-buzz
  age.secrets.glen-buzz-nsecs = {
    file = ../../secrets/glen-buzz-nsecs.age;
    mode = "0440";
    group = "users";
  };
}
