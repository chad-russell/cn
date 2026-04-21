# Gloo Dev Stack Secrets

Age-encrypted secrets for the Gloo dev stack. Decrypted at runtime by `dev.sh`.

## Prerequisites

- Age key at `~/.config/age/key.txt`
- Age binary (`brew install age` or system package)

## Public Key

```
age1uhmefj4e0jhf4nza9efsdz9qa8fq08sf04c3jh268cf3uhmlypfqh60u2v
```

## Encrypted Files

| File | Contents |
|------|----------|
| `gloo-secrets.env.age` | `BETTER_AUTH_SECRET`, `HUMMINGBIRD_API_KEY`, `WORKOS_API_KEY`, `WORKOS_COOKIE_PASSWORD`, `INTEGRATION_ENCRYPTION_KEY`, `SESSION_SECRET` |

## Manual Decryption

```bash
age -d -i ~/.config/age/key.txt gloo-secrets.env.age
```

## How Secrets Are Loaded

`dev.sh` decrypts `gloo-secrets.env.age` to a temp file, sources it alongside the host-envs file, then deletes the temp file. This means:

- Host envs files (`host-envs/*.env`) contain **non-secret config** (ports, endpoints, localhost addresses)
- The encrypted secrets file contains **actual secret values** (API keys, auth secrets)
- Both are loaded before the dev process starts, with secrets overriding any defaults

## Rotating / Adding Secrets

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
