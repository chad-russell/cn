# ── glen channel plugins (Stoat bridge) ─────────────────────────────
# The @glen/channel-stoat plugin (source of truth: ~/glen repo,
# plugins/channel-stoat) bridges the self-hosted Stoat instance
# (loopback :8880, rootless podman on bee) into dsh sessions. Deployed
# into the glen profile's node_modules by the glen repo's sync flow —
# this module only provides the secret.
#
# The bot TOKEN is boot-consumed (dsh-web unit env via modules/dsh.nix)
# → agenix, never in patch files or the repo. Channel/user ids are
# non-secret config and live in the DSH_HOME overlay.
{
  age.secrets.glen-buzz-bot-nsec = {
    file = ../../secrets/glen-buzz-bot-nsec.age;
    mode = "0440";
    group = "users";
  };

  # per-persona nostr identities (glen/coder/gloo/nsfw) — env-file format
  # GLEN_BUZZ_NSEC_<PERSONA>=<hex>, consumed by @glen/channel-buzz
  age.secrets.glen-buzz-nsecs = {
    file = ../../secrets/glen-buzz-nsecs.age;
    mode = "0440";
    group = "users";
  };

  age.secrets.glen-stoat-token = {
    file = ../../secrets/glen-stoat-token.age;
    mode = "0440";
    group = "users";
  };
}
