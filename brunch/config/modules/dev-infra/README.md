# Dev Infra Brunch Module

Shared development infrastructure used by multiple stack modules.

It currently manages:

- `dev.network`
- `dev-postgres-data.volume`
- `dev-postgres.container`

That produces these generated user services after `systemctl --user daemon-reload`:

- `dev-network.service`
- `dev-postgres-data-volume.service`
- `dev-postgres.service`
