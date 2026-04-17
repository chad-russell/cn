# Security Audit: Plaintext Secrets

This document tracks all plaintext secrets found in the repository and plans for mitigation before public hosting.

## Status: ✅ RESOLVED

All plaintext secrets have been encrypted with age and the repo is ready for public hosting.

## Implementation Summary

| File | Secret Type | Status |
|------|-------------|--------|
| `servers/hub/quadlets/secrets/immich.env.age` | PostgreSQL password | ✅ Encrypted |
| `servers/hub/quadlets/secrets/karakeep.env.age` | Meili master key + NextAuth secret | ✅ Encrypted |
| `servers/hub/quadlets/secrets/searxng-settings.yml.age` | SearXNG settings file | ✅ Encrypted |

## Decryption

Secrets are decrypted by `setup-quadlets.sh` using the age key at `~/.config/age/key.txt`.

See `servers/hub/quadlets/secrets/README.md` for full documentation.

---

## Historical Findings (Resolved)

### 1. Immich PostgreSQL Password

**Locations:**
- `servers/hub/quadlets/containers/immich-postgres.container:12`
- `servers/hub/quadlets/pods/immich/immich.yml:19`
- `servers/hub/quadlets/pods/immich/immich.yml:59`
- `servers/hub/quadlets/pods/immich/immich.yml:93`

**Exposed value:** `immich_secret_password_change_me`

**Mitigation options:**
1. **Podman secrets** - Create a Podman secret and reference via `Secret=` in quadlet
2. **Environment file** - Use `EnvironmentFile=` pointing to a file outside the repo (already gitignored via `*.env`)
3. **Systemd credential** - Use systemd's `LoadCredential=` mechanism

**Recommended:** Option 2 (EnvironmentFile) - simplest, works with current quadlet structure.

### 2. Beszel Agent Tokens + SSH Keys

**Locations:**
- `servers/hub/quadlets/containers/beszel-agent.container:14-15`
- `servers/media/quadlets/containers/beszel-agent.container:14-15`

**Exposed values:**
- Hub agent: `TOKEN=2c13eff1-0f6f-4b1c-b216-aa61c0fec712`
- Media agent: `TOKEN=55f10155-7a92-4e2b-9fd4-4b08d5436ab1`
- Shared SSH key: `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSF6CQSQRZYRw5VkfmTwAQt0KkHLDhx9ukqNzryWLv1`

**Risk:** High - tokens allow agent registration, SSH key could be used for authentication elsewhere.

**Mitigation:** 
1. Rotate both tokens in Beszel hub UI
2. Regenerate the SSH key pair
3. Use EnvironmentFile for all three values

### 3. Karakeep Secrets

**Location:** `servers/hub/quadlets/pods/karakeep/karakeep.yml:18-20`

**Exposed values:**
- `MEILI_MASTER_KEY: karakeep-master-key-change-me`
- `NEXTAUTH_SECRET: change-me-or-use-a-secret`

**Mitigation:**
1. Generate new secure values
2. Use Kubernetes-style secret references or env files (Podman pods support `--env-file`)

### 4. SearXNG Secret Key

**Location:** `servers/hub/quadlets/config/searxng-settings.yml:21`

**Exposed value:** `30d4cf69b8b8c2d990bd8f778a499fb90f5e337c4a966b911d02152c59aebff9`

**Mitigation:**
1. Regenerate the key: `openssl rand -hex 32`
2. Option A: Move entire settings file out of repo (it's mounted from `/srv/searxng/`)
3. Option B: Use environment variable substitution in settings file (SearXNG supports `SEARXNG_SECRET`)

**Recommended:** Option A - the settings file is already mounted from host, not from repo. Remove it from repo entirely.

---

## Mitigation Plan

### Phase 1: Immediate Actions (Before Publishing)

1. **Rotate all exposed secrets:**
   - [ ] Regenerate Immich PostgreSQL password
   - [ ] Rotate Beszel tokens (delete and re-add agents in hub UI)
   - [ ] Regenerate Beszel SSH key pair
   - [ ] Generate new Karakeep secrets
   - [ ] Regenerate SearXNG secret key

2. **Remove secrets from repo:**
   - [ ] Replace hardcoded passwords with `{{SECRET_NAME}}` placeholders
   - [ ] Remove `servers/hub/quadlets/config/searxng-settings.yml` from repo (it lives on host at `/srv/searxng/`)

3. **Create secret template files:**
   - [ ] Create `servers/hub/quadlets/secrets/.env.example` with all required variables
   - [ ] Document how to generate each secret

### Phase 2: Implement Secret Management

For each service, implement one of these patterns:

**Pattern A: Environment Files (Recommended for most services)**
```ini
# In quadlet .container file:
EnvironmentFile=%h/.config/containers/systemd/secrets/<service>.env

# In secrets/<service>.env:
POSTGRES_PASSWORD=<actual-secret>
```

**Pattern B: Podman Secrets (For highly sensitive secrets)**
```bash
# Create secret
echo "my-password" | podman secret create postgres_password -

# Reference in quadlet
Secret=postgres_password,type=env,target=POSTGRES_PASSWORD
```

### Files to Modify

1. `servers/hub/quadlets/containers/immich-postgres.container`
   - Replace `Environment=POSTGRES_PASSWORD=...` with `EnvironmentFile=...`

2. `servers/hub/quadlets/containers/beszel-agent.container`
   - Replace TOKEN and KEY env vars with `EnvironmentFile=...`

3. `servers/media/quadlets/containers/beszel-agent.container`
   - Same as above

4. `servers/hub/quadlets/pods/immich/immich.yml`
   - Convert to using environment variable references or env files

5. `servers/hub/quadlets/pods/karakeep/karakeep.yml`
   - Convert to using environment variable references

6. `servers/hub/quadlets/config/searxng-settings.yml`
   - Delete from repo (copy to `/srv/searxng/settings.yml` on host first)

### New Files to Create

1. `servers/hub/quadlets/secrets/README.md` - Documentation for secret management
2. `servers/hub/quadlets/secrets/*.env.example` - Template files for each service

### Update .gitignore

Ensure these patterns are in root `.gitignore`:
```gitignore
# Secrets
*.env
!*.env.example
secrets/
```

---

## Verification Checklist

Before publishing the repo:

- [x] Run: `grep -rE "(password|token|secret|key)\s*=\s*['\"][^'\"]+['\"]" servers/` (should only match placeholders)
- [x] Run: `grep -rE "ssh-rsa|ssh-ed25519" servers/` (should return nothing)
- [x] Verify no UUID-like tokens in any config files
- [x] Confirm all `.env` files are gitignored
- [ ] Test deployment with new secret setup on a clean machine

---

## Notes

- Nebula PKI is already properly gitignored via `nebula/.gitignore`
- The `.archived/` directory is already gitignored
- No secrets found in peekaping monitors.json (only URLs, no auth)
