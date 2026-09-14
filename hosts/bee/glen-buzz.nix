# ── glen buzz persona identities (agenix) ─────────────────────────────
# Per-persona nostr identities for the buzz relay (buzz.internal.crussell.io).
# Consumed by the server-side buzz-acp harnesses (hosts/bee/buzz-acp.nix)
# via the unit EnvironmentFile — the persona nsec signs the agent's relay
# traffic; the custom @glen/channel-buzz dsh plugin that used these before
# was removed 2026-09-14 in favor of that architecture.
{
  # per-persona nostr identities (glen/gloo) — env-file format
  # GLEN_BUZZ_NSEC_<PERSONA>=<hex>
  age.secrets.glen-buzz-nsecs = {
    file = ../../secrets/glen-buzz-nsecs.age;
    mode = "0440";
    group = "users";
  };
}
