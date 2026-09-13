# Buzz relay (block/buzz) — the household chat substrate on bee.
#
# Canonical upstream compose (relay + postgres + redis + minio, 4 containers)
# at ~/buzz/deploy (compose.yml from deploy/compose/, secrets in .env 0600).
# This unit manages lifecycle like `stoat`: oneshot RemainAfterExit over the
# rootless podman socket. Data in named volumes (postgres, minio, git).
#
# Network: relay publishes 127.0.0.1:3212; the stack needs NO other ingress —
# bees caddy fronts https://buzz.internal.crussell.io → 10.10.0.12:3212
# (WebSocket-native). RELAY_OWNER_PUBKEY pins the relay owner identity
# (keypair generated with nak; hex private key in the Glen Proton Pass vault
# item 'buzz relay owner identity' + .env BUZZ_RELAY_PRIVATE_KEY).
#
# `systemctl start/stop buzz` = compose up/down (volumes preserved).
{ config, pkgs, ... }:

{
  systemd.services.buzz = {
    description = "Buzz relay (nostr NIP-29) — household chat substrate";
    wants = [ "network-online.target" "podman-user.socket" ];
    after = [ "network-online.target" "podman-user.socket" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "crussell";
      WorkingDirectory = "/home/crussell/buzz/deploy";
      Environment = [
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DOCKER_HOST=unix:///run/user/1000/podman/podman.sock"
      ];
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d --remove-orphans";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      TimeoutStartSec = 300;
      TimeoutStopSec = 120;
    };

    wantedBy = [ "multi-user.target" ];
  };
}
