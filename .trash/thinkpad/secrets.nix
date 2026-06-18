let
  # Public keys for encrypting secrets.
  # Add more user/host keys here as needed.
  user = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora";
in
{
  "secrets/zhipu-api-key.age".publicKeys = [ user ];
  "secrets/openrouter-api-key.age".publicKeys = [ user ];
}
