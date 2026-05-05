let
  # SSH ed25519 public key — decrypt with: age -d -i ~/.ssh/id_ed25519 <file>.age
  crussell = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpNEpdHo8X0L9rgsJ+8fuXA4DodZftJaCd3Q6eCrVsw crussell@fedora";
in
{
  "ca.key.age".publicKeys = [ crussell ];
  "bee-host.key.age".publicKeys = [ crussell ];
  "bees.key.age".publicKeys = [ crussell ];
  "crussell-lh-local.key.age".publicKeys = [ crussell ];
  "hetzner-lighthouse.key.age".publicKeys = [ crussell ];
  "k1.key.age".publicKeys = [ crussell ];
  "k2-host.key.age".publicKeys = [ crussell ];
  "k2.key.age".publicKeys = [ crussell ];
  "k3.key.age".publicKeys = [ crussell ];
  "k4.key.age".publicKeys = [ crussell ];
  "nas.key.age".publicKeys = [ crussell ];
  "phone.key.age".publicKeys = [ crussell ];
  "thinkpad.key.age".publicKeys = [ crussell ];
}
