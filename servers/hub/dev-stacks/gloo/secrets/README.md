# Gloo Dev Stack Secrets

Age-encrypted secrets for the Gloo dev stack.

## Prerequisites

- Age key at `~/.config/age/key.txt`
- Age binary (`brew install age` or system package)

## Public Key

```text
age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v
```

## Encrypted Files

| File | Contents |
|------|----------|
| `gloo-secrets.env.age` | `BETTER_AUTH_SECRET`, `HUMMINGBIRD_API_KEY`, `WORKOS_API_KEY`, `WORKOS_COOKIE_PASSWORD`, `INTEGRATION_ENCRYPTION_KEY`, `SESSION_SECRET` |

## How secrets are used

At app service start:

1. `systemd --user` runs `render-runtime-env.sh <service>`
2. The script copies `host-envs/<service>.env`
3. It decrypts `gloo-secrets.env.age`
4. It writes a merged runtime env file to:

```text
/run/user/$UID/gloo/<service>.env
```

That runtime file is then sourced by `run-service.sh` before the dev server starts.

## Manual decryption

```bash
age -d -i ~/.config/age/key.txt gloo-secrets.env.age
```

## Rotating / adding secrets

1. Decrypt to plaintext:
   ```bash
   age -d -i ~/.config/age/key.txt gloo-secrets.env.age > /tmp/gloo-secrets.env
   ```
2. Edit `/tmp/gloo-secrets.env`
3. Re-encrypt:
   ```bash
   age -e -r age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v \
     -o gloo-secrets.env.age /tmp/gloo-secrets.env
   ```
4. Delete plaintext:
   ```bash
   rm /tmp/gloo-secrets.env
   ```
