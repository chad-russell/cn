# ── Prometheus Metrics Server ──────────────────────────────────────
#
# Central Prometheus instance scraping node_exporter from all NixOS hosts.
# Listens on localhost:9090 only (accessed by the homelab monitor script).
# Retains 15 days of data. No external access needed.

{ ... }:

{
  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    retentionTime = "15d";

    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "60s";
        static_configs = [
          {
            targets = [
              "localhost:9100"     # bees (self)
              "10.10.0.12:9100"   # bee (Nebula)
              "10.10.0.10:9100"   # think (Nebula)
            ];
          }
        ];
      }
    ];
  };
}
