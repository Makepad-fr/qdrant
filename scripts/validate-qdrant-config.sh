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
canary_env = read_required_text(repo_root / "envs/canary/.env.qdrant", "canary Qdrant env file")
production_env = read_required_text(repo_root / "envs/production/.env.qdrant", "production Qdrant env file")
manual_deploy = read_required_text(repo_root / ".github/workflows/manual-deploy.yml", "manual deploy workflow")
normalized_readme = re.sub(r"\s+", " ", readme)

for service in ("codegraph-qdrant", "opsbrain-qdrant"):
    require(service in base_compose, f"Base Compose file must define {service}.")

for variable in (
    "MAKEPAD_QDRANT_CODEGRAPH_NETWORK",
    "MAKEPAD_QDRANT_OPSBRAIN_NETWORK",
    "MAKEPAD_QDRANT_CODEGRAPH_HTTP_PORT",
    "MAKEPAD_QDRANT_CODEGRAPH_GRPC_PORT",
    "MAKEPAD_QDRANT_OPSBRAIN_HTTP_PORT",
    "MAKEPAD_QDRANT_OPSBRAIN_GRPC_PORT",
    "MAKEPAD_QDRANT_CODEGRAPH_DATA_PATH",
    "MAKEPAD_QDRANT_OPSBRAIN_DATA_PATH",
):
    require(variable in base_compose, f"Base Compose file must use {variable}.")
    if variable.endswith("_NETWORK"):
        require(variable in manual_deploy, f"Manual deploy workflow must handle {variable}.")
    else:
        require(variable in canary_env, f"Canary env must define {variable}.")
        require(variable in production_env, f"Production env must define {variable}.")

for secret in (
    "DEPLOY_CODEGRAPH_QDRANT_NETWORK",
    "DEPLOY_OPSBRAIN_QDRANT_NETWORK",
    "DEPLOY_CODEGRAPH_QDRANT_API_KEY",
    "DEPLOY_OPSBRAIN_QDRANT_API_KEY",
):
    require(secret in normalized_readme, f"README must document {secret}.")
    require(secret in manual_deploy, f"Manual deploy workflow must require {secret}.")

require("DEPLOY_SSH_USER=root" in normalized_readme, "README must document that root SSH deploys are rejected.")
require("DEPLOY_SSH_USER must not be root" in manual_deploy, "Manual deploy workflow must reject root SSH users.")
require("docker stack deploy" not in manual_deploy, "Manual deploy workflow must not deploy with Docker Swarm.")
require("docker network create" not in manual_deploy, "Manual deploy workflow must not create app-owned networks.")
require("Required Docker network" in manual_deploy, "Manual deploy workflow must fail clearly when app-owned networks are missing.")
require("up -d" in manual_deploy, "Manual deploy workflow must use standalone Docker Compose up.")
require("network_mode: host" not in base_compose, "Base Compose file must not use host networking.")
require("external: true" in base_compose, "Base Compose file must use external Docker networks.")
require("makepad-qdrant-codegraph" in base_compose, "Base Compose file must define the Codegraph alias.")
require("makepad-qdrant-opsbrain" in base_compose, "Base Compose file must define the Opsbrain alias.")
require("restart: unless-stopped" in base_compose, "Base Compose file must restart standalone containers unless stopped.")
require("/etc/makepad/qdrant/codegraph.env" in base_compose, "Base Compose file must read Codegraph API key from /etc.")
require("/etc/makepad/qdrant/opsbrain.env" in base_compose, "Base Compose file must read Opsbrain API key from /etc.")
require("QDRANT__SERVICE__API_KEY" in manual_deploy, "Manual deploy workflow must write Qdrant API-key env files.")
require("QDRANT_URL=http://makepad-qdrant-codegraph:6333" in readme, "README must document Codegraph Qdrant URL.")
require("QDRANT_URL=http://makepad-qdrant-opsbrain:6333" in readme, "README must document Opsbrain Qdrant URL.")
require("QDRANT_COLLECTION=document_chunks" in readme, "README must document Opsbrain Qdrant collection.")
require("Do not expose Qdrant publicly" in readme, "README must warn against public Qdrant exposure.")
require("Docker Swarm" in readme and "not Docker Swarm stack" in readme, "README must state this is not a Swarm stack.")
require("standalone Docker Compose" in agents, "AGENTS must document standalone Docker Compose.")
require("app-owned attachable overlay" in readme, "README must document app-owned attachable overlay network requirements.")
require("does not create Docker networks" in readme, "README must document that Qdrant deploys do not create app-owned networks.")

for text, label in ((canary_env, "canary env"), (production_env, "production env")):
    require("MAKEPAD_QDRANT_CODEGRAPH_DATA_PATH=" in text, f"{label} must define Codegraph data path.")
    require("MAKEPAD_QDRANT_OPSBRAIN_DATA_PATH=" in text, f"{label} must define Opsbrain data path.")
    require("API_KEY" not in text, f"{label} must not contain API keys.")
    require("MAKEPAD_QDRANT_CODEGRAPH_ENV_FILE=/etc/makepad/qdrant/codegraph.env" in text, f"{label} must point Codegraph to /etc secret env.")
    require("MAKEPAD_QDRANT_OPSBRAIN_ENV_FILE=/etc/makepad/qdrant/opsbrain.env" in text, f"{label} must point Opsbrain to /etc secret env.")

for forbidden in ("change-me", "password123", "replace-this", "secret-api-key"):
    require(forbidden not in readme + base_compose + manual_deploy, f"Repository text must not contain placeholder secret {forbidden}.")

require("qdrant/qdrant:v1.15.5" in base_compose, "Base Compose file must pin the Qdrant image version.")
require("6333" in production_env, "Production env must use expected Qdrant HTTP ports.")
require("6333" in canary_env, "Canary env must use expected Qdrant HTTP ports.")
PY
