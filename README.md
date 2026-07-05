# Makepad Qdrant

Shared Qdrant deployment for Makepad-fr applications.

This repository owns the shared Qdrant servers used by Makepad-fr projects. Qdrant is deployed on the DB/vector VM as standalone Docker Compose containers, matching the live PostgreSQL deployment style, while joining app-specific external Docker networks for application access. Application repositories should not deploy Qdrant directly in canary or production when they use this shared infrastructure.

## Layout

- `compose.yml`: base Qdrant service definitions
- `envs/canary/.env.qdrant`: canary Qdrant settings
- `envs/production/.env.qdrant`: production Qdrant settings
- `.github/workflows/manual-deploy.yml`: manual deployment workflow
- `scripts/validate-qdrant-config.sh`: local static validation

## Services

This stack intentionally runs separate Qdrant services for Codegraph and Opsbrain:

| Project | Service | Alias | Default data path |
| --- | --- | --- | --- |
| Codegraph | `codegraph-qdrant` | `makepad-qdrant-codegraph` | `/var/lib/makepad/qdrant-codegraph` |
| Opsbrain | `opsbrain-qdrant` | `makepad-qdrant-opsbrain` | `/var/lib/makepad/qdrant-opsbrain` |

Do not collapse these into one shared collection with `project_id`. Codegraph stores metadata-only code vectors scoped by project, while Opsbrain stores company document vectors scoped by company. Separate Qdrant instances give each product independent API keys, backups, upgrades, resource limits, and reindex windows.

## Runtime Model

Qdrant runs with:

- standalone Docker Compose, not Docker Swarm stack
- one container per product
- one persistent bind mount per product
- one API key env file per product under `/etc/makepad/qdrant/`
- one app-specific external Docker network per product
- `restart: unless-stopped`

The external networks are expected to be app-owned attachable overlay networks when the consumers are Swarm services. This lets application stacks attach to their own isolated network while Qdrant remains a standalone Compose container instead of a Swarm service.

The deploy workflow does not create Docker networks. If a configured network is missing on the target Docker engine, deployment fails clearly. The consuming application repository owns creation and lifecycle of its app network.

## Networks

The Qdrant services join external Docker networks configured through Compose:

- `${MAKEPAD_QDRANT_CODEGRAPH_NETWORK}`
- `${MAKEPAD_QDRANT_OPSBRAIN_NETWORK}`

The manual deploy workflow sources these Compose variables from environment secrets with this mapping:

- `${MAKEPAD_QDRANT_CODEGRAPH_NETWORK}` <- `DEPLOY_CODEGRAPH_QDRANT_NETWORK`
- `${MAKEPAD_QDRANT_OPSBRAIN_NETWORK}` <- `DEPLOY_OPSBRAIN_QDRANT_NETWORK`

Application network topology is owned by the consuming application repositories. Codegraph should create/own and attach to the Codegraph Qdrant network, then use `makepad-qdrant-codegraph`. Opsbrain should create/own and attach to the Opsbrain Qdrant network, then use `makepad-qdrant-opsbrain`.

Both containers listen on the normal Qdrant ports inside their isolated networks:

| Project | HTTP port | gRPC port |
| --- | ---: | ---: |
| Codegraph | `6333` | `6334` |
| Opsbrain | `6333` | `6334` |

Do not expose Qdrant publicly. Self-hosted Qdrant is not secure by default unless API keys and network restrictions are configured.

## Deployment

Use the manual GitHub Actions workflow in this repository.

Required environment secrets:

- `DEPLOY_SSH_HOST`
- `DEPLOY_SSH_PORT`
- `DEPLOY_SSH_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_REMOTE_DIR`
- `DEPLOY_CODEGRAPH_QDRANT_NETWORK`
- `DEPLOY_OPSBRAIN_QDRANT_NETWORK`
- `DEPLOY_CODEGRAPH_QDRANT_API_KEY`
- `DEPLOY_OPSBRAIN_QDRANT_API_KEY`

Optional environment secret:

- `DEPLOY_REMOTE_CONFIG_DIR`: defaults to `/etc/makepad/qdrant`

`DEPLOY_SSH_USER` must be a non-root deployment account with the Docker permissions needed to run Docker Compose and inspect Docker networks. The workflow rejects `DEPLOY_SSH_USER=root`. It uses `sudo` only for writing root-owned secret env files under `/etc/makepad/qdrant`.

The workflow deploys only the Qdrant containers. It does not create Docker networks, modify firewall rules, deploy applications, or create collections.

## Application Configuration

Codegraph should use:

```text
QDRANT_URL=http://makepad-qdrant-codegraph:6333
QDRANT_API_KEY=<codegraph qdrant api key>
```

Opsbrain should use:

```text
QDRANT_URL=http://makepad-qdrant-opsbrain:6333
QDRANT_API_KEY=<opsbrain qdrant api key>
QDRANT_COLLECTION=document_chunks
```

If an application connects through the DB VM host instead of an isolated Docker network, keep the Qdrant ports firewall-restricted to the application hosts.

## Data And Backups

Each Qdrant service has its own persistent data directory:

- Codegraph: `${MAKEPAD_QDRANT_CODEGRAPH_DATA_PATH}`
- Opsbrain: `${MAKEPAD_QDRANT_OPSBRAIN_DATA_PATH}`

Use Qdrant snapshots for collection backups and restore drills. Snapshot automation is intentionally not included here yet because storage destination and retention policy should be decided with the rest of the Makepad backup model.

Changing an embedding model or vector dimension requires reindexing the affected product data. Keep this product-local:

- Codegraph reindexes code chunks from its metadata/Postgres/Neo4j inputs.
- Opsbrain reprocesses document chunks from its Postgres/MinIO source data.

## Validation

Run local static checks before opening a deployment PR:

```bash
bash scripts/validate-qdrant-config.sh
```
