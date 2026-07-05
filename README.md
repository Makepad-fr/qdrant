# Makepad Qdrant

Shared Qdrant deployment for Makepad-fr applications.

This repository owns the shared Qdrant servers used by Makepad-fr projects. Application repositories connect through app-specific overlay network aliases or through a tightly firewalled DB VM host endpoint, depending on their deployment topology. Application repositories should not deploy Qdrant directly in canary or production when they use this shared infrastructure.

## Layout

- `compose.yml`: base Qdrant service definitions
- `envs/canary/compose.yml`: canary Swarm overrides
- `envs/canary/.env.qdrant`: canary Qdrant settings
- `envs/production/compose.yml`: production Swarm overrides
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

## Networks

The Qdrant services join external overlay networks configured through Compose:

- `${MAKEPAD_QDRANT_CODEGRAPH_NETWORK}`
- `${MAKEPAD_QDRANT_OPSBRAIN_NETWORK}`

The manual deploy workflow sources these Compose variables from environment secrets with this mapping:

- `${MAKEPAD_QDRANT_CODEGRAPH_NETWORK}` <- `DEPLOY_CODEGRAPH_QDRANT_NETWORK`
- `${MAKEPAD_QDRANT_OPSBRAIN_NETWORK}` <- `DEPLOY_OPSBRAIN_QDRANT_NETWORK`

Application network topology is owned by the consuming application repositories. Stacks attached to the Codegraph Qdrant network should use the stable service alias `makepad-qdrant-codegraph`. Stacks attached to the Opsbrain Qdrant network should use `makepad-qdrant-opsbrain`.

## Node Labels

Pin the shared Qdrant services to the database/vector node:

```bash
docker node update --label-add infra.makepad.qdrant=true <db-node>
```

The Swarm placement constraint is:

```text
node.labels.infra.makepad.qdrant == true
```

If Qdrant later needs its own VM, move this label to the new node and redeploy the stack after moving/restoring data.

## Deployment

Use the manual GitHub Actions workflow in this repository.

Required environment secrets:

- `DEPLOY_SSH_HOST`
- `DEPLOY_SSH_PORT`
- `DEPLOY_SSH_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_REMOTE_DIR`
- `DEPLOY_STACK_NAME`
- `DEPLOY_CODEGRAPH_QDRANT_NETWORK`
- `DEPLOY_OPSBRAIN_QDRANT_NETWORK`
- `DEPLOY_CODEGRAPH_QDRANT_API_KEY`
- `DEPLOY_OPSBRAIN_QDRANT_API_KEY`

`DEPLOY_SSH_USER` must be a non-root deployment account with the Docker permissions needed to create overlay networks and deploy the stack. The workflow rejects `DEPLOY_SSH_USER=root`.

The workflow deploys only the Qdrant stack. If one of the configured Qdrant networks does not exist yet, it is created on the manager before deployment.

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

If an application connects through the DB VM host instead of an overlay network, keep the Qdrant ports firewall-restricted to the application hosts. Do not expose Qdrant publicly.

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
