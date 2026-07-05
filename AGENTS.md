# Repository Conventions

## Deploy Layout

- This repository owns standalone shared Qdrant containers for Makepad-fr applications.
- Application repositories should not deploy their own production Qdrant service when using this shared host.
- Keep Codegraph and Opsbrain Qdrant services separate. They have different collection semantics, upgrade windows, backup needs, and API keys.
- Runtime settings live under `envs/<environment>/.env.qdrant`.
- Secret API key env files live on the host under `/etc/makepad/qdrant/` and are not committed.

## Placement

- Qdrant runs as standalone Docker Compose containers on the DB/vector VM, matching the live PostgreSQL deployment style.
- Use `network_mode: host`, persistent bind mounts, and `restart: unless-stopped`.

## Security

- Do not commit API keys or generated access tokens.
- Deploy workflow inputs for API keys must come from GitHub environment secrets.
- Qdrant must remain reachable only through explicitly whitelisted DB-host firewall rules.

## Documentation

- Keep `README.md`, validation scripts, and workflow instructions aligned with deployment steps and service aliases.
