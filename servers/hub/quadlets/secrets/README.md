# Secrets Management

This directory contains age-encrypted secrets for the hub server. Secrets are decrypted during setup by `setup-quadlets.sh`.

## Prerequisites

- **Age key:** `~/.config/age/key.txt`
- **Age binary:** Install from https://github.com/FiloSottile/age#installation

The public key for this repository is:
```
age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v
```

## Encrypted Files

| File | Decrypted To | Variables |
|------|--------------|-----------|
| `immich.env.age` | `/srv/immich/secrets.env` | `POSTGRES_PASSWORD` |
| `karakeep.env.age` | `/srv/karakeep/secrets.env` | `MEILI_MASTER_KEY`, `NEXTAUTH_SECRET` |
| `beszel-hub.env.age` | `/srv/beszel/secrets.env` | `BESZEL_TOKEN`, `BESZEL_KEY` |
| `searxng-settings.yml.age` | `/srv/searxng/settings.yml` | Full SearXNG settings file |

## Manual Decryption

If you need to decrypt secrets manually:

```bash
age -d -i ~/.config/age/key.txt secrets/immich.env.age > /srv/immich/secrets.env
```

## Rotating Secrets

1. **Generate new secret:**
   ```bash
   openssl rand -base64 32
   ```

2. **Create new plaintext file:**
   ```bash
   echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)" > immich.env
   ```

3. **Encrypt with age:**
   ```bash
   age -e -r age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v \
     immich.env > immich.env.age
   ```

4. **Remove plaintext file:**
   ```bash
   rm immich.env
   ```

5. **Redeploy:** Run `setup-quadlets.sh` or manually decrypt to `/srv/`.

## Beszel Tokens

Beszel tokens must be rotated through the Beszel hub UI:

1. Open Beszel hub at `https://beszel.internal.crussell.io`
2. Go to Settings → Agents
3. Delete the old agent entry
4. Add new agent - this generates a new token
5. Update `beszel-hub.env.age` with the new token

## Beszel SSH Key

The Beszel agent uses an SSH key for authentication. To rotate:

```bash
ssh-keygen -t ed25519 -f beszel_agent -N ""
```

Then update the `.env` files with:
- `BESZEL_KEY` = contents of `beszel_agent.pub`
- Deploy the private key to the Beszel hub

## Adding New Secrets

1. Create the plaintext file in this directory
2. Encrypt it:
   ```bash
   age -e -r age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v \
     <file> > <file>.age
   ```
3. Delete the plaintext file
4. Add decryption to `setup-quadlets.sh`
5. Update this README with the new file
