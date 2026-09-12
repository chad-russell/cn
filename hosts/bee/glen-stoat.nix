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
  age.secrets.glen-stoat-token = {
    file = ../../secrets/glen-stoat-token.age;
    mode = "0440";
    group = "users";
  };
}
