# Setting up git-crypt on k2, k3, k4 machines

## Option 1: Share the Same GPG Key (Simplest)

### On this machine (where git-crypt is already set up):

1. Export the GPG private key:
   ```bash
   gpg --armor --export-secret-keys 2461068A7ED1D45E6CE11CD12CEE031AFAF985E2 > onyx-gpg-key.asc
   ```

2. Securely transfer `onyx-gpg-key.asc` to each machine (k2, k3, k4).

### On each k2/k3/k4 machine:

1. **Install git-crypt** (if not already installed):
   ```bash
   nix-env -iA nixos.git-crypt
   # Or add to systemPackages in your NixOS config
   ```

2. **Import the GPG key**:
   ```bash
   gpg --import onyx-gpg-key.asc
   ```

3. **Clone/unlock the repository**:
   ```bash
   cd /path/to/repo
   git-crypt unlock
   ```

4. **Verify it worked**:
   ```bash
   cat secrets/onyx.secret
   # Should show the decrypted JSON, not encrypted gibberish
   ```

## Option 2: Use Separate GPG Keys Per Machine

### On each k2/k3/k4 machine:

1. **Generate a GPG key** (if you don't have one):
   ```bash
   gpg --gen-key
   # Follow prompts, use a descriptive name like "k2 Admin <k2@onyx.local>"
   ```

2. **Export your public key**:
   ```bash
   gpg --armor --export your-email@example.com > k2-public-key.asc
   ```

3. **Send the public key** to this machine (where git-crypt is set up).

### On this machine:

1. **Import the new public key**:
   ```bash
   gpg --import k2-public-key.asc
   ```

2. **Add the user to git-crypt**:
   ```bash
   git-crypt add-gpg-user your-email@example.com
   ```

3. **Commit the changes**:
   ```bash
   git add .git-crypt/
   git commit -m "Add GPG key for k2"
   git push
   ```

### Back on k2/k3/k4:

1. **Pull the changes**:
   ```bash
   git pull
   ```

2. **Unlock git-crypt**:
   ```bash
   git-crypt unlock
   ```

## For NixOS Deployment

After unlocking git-crypt on each machine, your `nixos-rebuild switch` will work normally because:
- The secrets are decrypted in your working directory
- Nix can read the decrypted `secrets/onyx.secret` file
- `secrets/secrets.nix` loads the JSON and exposes it via `config.mySecrets`

## Troubleshooting

If `nixos-rebuild switch` fails with errors about missing secrets:
- Make sure you've run `git-crypt unlock` on that machine
- Verify `secrets/onyx.secret` is readable and contains valid JSON
- Check that `secrets/secrets.nix` is being imported correctly

## Security Note

The GPG private key file (`onyx-gpg-key.asc`) contains sensitive material. After importing it on each machine, consider:
- Deleting the transfer file: `rm onyx-gpg-key.asc`
- Securing the GPG keyring: `chmod 700 ~/.gnupg`

