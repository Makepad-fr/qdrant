#!/usr/bin/env bash
set -euo pipefail

for binary in python3; do
  if ! command -v "${binary}" >/dev/null 2>&1; then
    echo "Missing required binary for qdrant validation: ${binary}" >&2
    exit 1
  fi
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "${script_dir}/.." && pwd)

REPO_ROOT="${repo_root}" python3 - <<'PY'
import os
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def read_required_text(path, label):
    require(path.is_file(), f"{label} is missing or is not a file: {path}")
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise SystemExit(f"Unable to read {label} at {path}: {error}") from error


repo_root = Path(os.environ["REPO_ROOT"])
readme = read_required_text(repo_root / "README.md", "README")
agents = read_required_text(repo_root / "AGENTS.md", "AGENTS")
base_compose = read_required_text(repo_root / "compose.yml", "base Compose file")
canary_compose = read_required_text(repo_root / "envs/canary/compose.yml", "canary Compose override")
production_compose = read_required_text(repo_root / "envs/production/compose.yml", "production Compose override")
canary_env = read_required_text(repo_root / "envs/canary/.env.qdrant", "canary Qdrant env file")
production_env = read_required_text(repo_root / "envs/production/.env.qdrant", "production Qdrant env file")
manual_deploy = read_required_text(repo_root / ".github/workflows/manual-deploy.yml", "manual deploy workflow")
normalized_readme = re.sub(r"\s+", " ", readme)

for service in ("codegraph-qdrant", "opsbrain-qdrant"):
    require(service in base_compose, f"Base Compose file must define {service}.")
    require(service in canary_compose, f"Canary Compose override must define {service}.")
    require(service in production_compose, f"Production Compose override must define {service}.")

for alias in ("makepad-qdrant-codegraph", "makepad-qdrant-opsbrain"):
    require(alias in base_compose, f"Base Compose file must define alias {alias}.")
    require(alias in normalized_readme, f"README must document alias {alias}.")

for variable in (
    "MAKEPAD_QDRANT_CODEGRAPH_NETWORK",
    "MAKEPAD_QDRANT_OPSBRAIN_NETWORK",
    "MAKEPAD_QDRANT_CODEGRAPH_API_KEY",
    "MAKEPAD_QDRANT_OPSBRAIN_API_KEY",
):
    require(variable in base_compose or variable.endswith("_NETWORK"), f"Base Compose file must use {variable} when relevant.")
    require(variable in manual_deploy, f"Manual deploy workflow must handle {variable}.")

for secret in (
    "DEPLOY_CODEGRAPH_QDRANT_NETWORK",
    "DEPLOY_OPSBRAIN_QDRANT_NETWORK",
    "DEPLOY_CODEGRAPH_QDRANT_API_KEY",
    "DEPLOY_OPSBRAIN_QDRANT_API_KEY",
):
    require(secret in normalized_readme, f"README must document {secret}.")
    require(secret in manual_deploy, f"Manual deploy workflow must require {secret}.")

require(
    "`${MAKEPAD_QDRANT_CODEGRAPH_NETWORK}` <- `DEPLOY_CODEGRAPH_QDRANT_NETWORK`" in normalized_readme,
    "README must document Codegraph network secret mapping.",
)
require(
    "`${MAKEPAD_QDRANT_OPSBRAIN_NETWORK}` <- `DEPLOY_OPSBRAIN_QDRANT_NETWORK`" in normalized_readme,
    "README must document Opsbrain network secret mapping.",
)
require("DEPLOY_SSH_USER=root" in normalized_readme, "README must document that root SSH deploys are rejected.")
require("DEPLOY_SSH_USER must not be root" in manual_deploy, "Manual deploy workflow must reject root SSH users.")
require("docker network create --driver overlay --attachable" in manual_deploy, "Manual deploy workflow must create missing overlay networks.")
require("docker stack deploy" in manual_deploy, "Manual deploy workflow must deploy with Docker Swarm.")
require("QDRANT__SERVICE__API_KEY" in base_compose, "Base Compose file must enable Qdrant API-key auth.")
require("QDRANT_URL=http://makepad-qdrant-codegraph:6333" in readme, "README must document Codegraph Qdrant URL.")
require("QDRANT_URL=http://makepad-qdrant-opsbrain:6333" in readme, "README must document Opsbrain Qdrant URL.")
require("QDRANT_COLLECTION=document_chunks" in readme, "README must document Opsbrain Qdrant collection.")
require("Do not expose Qdrant publicly" in readme, "README must warn against public Qdrant exposure.")
require("node.labels.infra.makepad.qdrant == true" in production_compose, "Production Compose must pin Qdrant to the qdrant node label.")
require("node.labels.infra.makepad.qdrant == true" in canary_compose, "Canary Compose must pin Qdrant to the qdrant node label.")
require("node.labels.infra.makepad.qdrant == true" in readme, "README must document the qdrant node label.")
require("node.labels.infra.makepad.qdrant == true" in agents, "AGENTS must document the qdrant node label.")

for text, label in ((canary_env, "canary env"), (production_env, "production env")):
    require("MAKEPAD_QDRANT_CODEGRAPH_DATA_PATH=" in text, f"{label} must define Codegraph data path.")
    require("MAKEPAD_QDRANT_OPSBRAIN_DATA_PATH=" in text, f"{label} must define Opsbrain data path.")
    require("API_KEY" not in text, f"{label} must not contain API keys.")

for forbidden in ("change-me", "password123", "replace-this", "secret-api-key"):
    require(forbidden not in readme + base_compose + manual_deploy, f"Repository text must not contain placeholder secret {forbidden}.")

require("qdrant/qdrant:v1.15.5" in base_compose, "Base Compose file must pin the Qdrant image version.")
require("memory: 24G" in production_compose, "Production Compose must set per-service memory limits.")
require("memory: 8G" in canary_compose, "Canary Compose must set per-service memory limits.")
PY
