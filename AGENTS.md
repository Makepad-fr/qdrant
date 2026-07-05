# Repository Conventions

## Deploy Layout

- This repository owns shared Qdrant stacks for Makepad-fr applications.
- Application repositories own their app-specific network topology and should not deploy their own production Qdrant service when using this shared stack.
- Keep Codegraph and Opsbrain Qdrant services separate. They have different collection semantics, upgrade windows, backup needs, and API keys.
- Canary and production overrides live under `envs/<environment>/compose.yml`.
- Qdrant env files live under `envs/<environment>/.env.qdrant`.

## Placement

- Qdrant is pinned with `node.labels.infra.makepad.qdrant == true`.
- On the current DB VM, this can be the same physical node as PostgreSQL, but keep the labels separate so either service can move later.

## Security

- Do not commit API keys or generated access tokens.
- Deploy workflow inputs for API keys must come from GitHub environment secrets.
- Qdrant must remain reachable only through the configured private overlay networks or explicitly whitelisted DB-host firewall rules.

## Documentation

- Keep `README.md`, validation scripts, and workflow instructions aligned with deployment steps and service aliases.
