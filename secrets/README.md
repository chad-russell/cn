# Secret Management with git-crypt

This repository uses [git-crypt](https://github.com/AGWA/git-crypt) to manage secrets. This allows us to commit encrypted secrets to the repository while keeping them readable for authorized users and the deployment system.

## Prerequisites

- `git-crypt` installed on your machine
- GPG key configured

## Structure

- `secrets/secrets.nix`: Nix module that loads decrypted secrets and exposes them to the NixOS configuration
- `secrets/*.secret`: JSON files containing secrets (encrypted in git)
- `secrets/.gitattributes`: Configuration for which files git-crypt should encrypt

## Usage

### Adding a New Secret

1. Create or edit a secret file in the `secrets/` directory (e.g., `secrets/my-service.secret`).
2. Add your secrets as JSON content:
   ```json
   {
     "api_key": "your-super-secret-key",
     "db_password": "your-db-password"
   }
   ```
3. Git-crypt will automatically encrypt this file when you stage/commit it, thanks to `.gitattributes`.
4. Update `secrets/secrets.nix` to read this new file if needed.

### Using Secrets in Nix Configuration

Secrets are exposed via `config.mySecrets`. For example:

```nix
# In secrets/secrets.nix
config.mySecrets = {
  myService = readSecret ./my-service.secret;
};

# In services/my-service.nix
environment = {
  API_KEY = config.mySecrets.myService.api_key;
};
```

### Setup on a New Machine

1. **Clone the repository**:
   ```bash
   git clone <repo-url>
   cd <repo-dir>
   ```

2. **Unlock the repository**:
   You need the GPG private key that was added to git-crypt.
   ```bash
   git-crypt unlock
   ```
   
   If you don't have the GPG key, you'll need an existing admin to add your GPG key:
   
   **On the new machine:**
   1. Generate a GPG key if you don't have one: `gpg --gen-key`
   2. Export your public key: `gpg --armor --export your-email@example.com > my-key.asc`
   3. Send `my-key.asc` to an existing admin.

   **On the admin machine:**
   1. Import the new key: `gpg --import my-key.asc`
   2. Trust the key (optional but recommended): `gpg --edit-key <key-id>` -> `trust`
   3. Add the user to git-crypt: `git-crypt add-gpg-user your-email@example.com`
   4. Commit the changes to `.git-crypt/`.

## Verification

To verify that secrets are encrypted:
```bash
git-crypt status
```

To check what files are encrypted:
```bash
git-crypt status -e
```

## Troubleshooting

If `secrets/secrets.nix` fails to evaluate because a secret file is missing or empty (e.g., before unlocking), the configuration uses a fallback mechanism to return an empty set `{}`. This allows the system to build even if secrets aren't fully available, though services depending on them might fail to start correctly.

