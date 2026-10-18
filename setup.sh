#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { printf '\033[0;34m[INFO]\033[0m  %s\n' "$1"; }
ok()    { printf '\033[0;32m[OK]\033[0m    %s\n' "$1"; }
err()   { printf '\033[0;31m[ERROR]\033[0m %s\n' "$1" >&2; }

# Phase 1: Validate prerequisites
info "Checking prerequisites..."

for var in GITOPS_REPO_URL GITHUB_USERNAME GITHUB_PAT DOCKERHUB_USERNAME DOCKERHUB_PAT; do
  if [ -z "${!var:-}" ]; then
    err "Required environment variable $var is not set."
    echo ""
    echo "Usage:"
    echo "  export GITOPS_REPO_URL=https://github.com/<username>/<repo>"
    echo "  export GITHUB_USERNAME=<username>"
    echo "  export GITHUB_PAT=<personal-access-token>"
    echo "  export DOCKERHUB_USERNAME=<dockerhub-username>"
    echo "  export DOCKERHUB_PAT=<dockerhub-access-token>"
    echo "  ./setup.sh"
    exit 1
  fi
done

for cmd in kubectl git envsubst; do
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command '$cmd' not found in PATH."
    exit 1
  fi
done

if ! kubectl cluster-info &>/dev/null; then
  err "Cannot connect to Kubernetes cluster. Check your kubeconfig."
  exit 1
fi
ok "Prerequisites verified"

# Phase 2: Initialize GitOps repository
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

info "Initializing GitOps repository at ${GITOPS_REPO_URL}..."

REPO_URL_WITH_CREDS="https://${GITHUB_USERNAME}:${GITHUB_PAT}@${GITOPS_REPO_URL#https://}"

if git clone "$REPO_URL_WITH_CREDS" "$WORK_DIR/gitops-repo" 2>/dev/null; then
  cd "$WORK_DIR/gitops-repo"
else
  info "Repository appears empty, initializing..."
  mkdir -p "$WORK_DIR/gitops-repo"
  cd "$WORK_DIR/gitops-repo"
  git init -b main
  git remote add origin "$REPO_URL_WITH_CREDS"
fi

if [ -f "charts/app/Chart.yaml" ]; then
  info "GitOps repo already contains Helm chart, skipping push."
else
  cp -r "$SCRIPT_DIR/charts/app" .

  git add .
  git -c user.name="kargo-demo" -c user.email="kargo-demo@example.com" \
    commit -m "Initial Helm chart for Kargo demo"
  git push -u origin main
  ok "Helm chart pushed to ${GITOPS_REPO_URL}"
fi

cd "$SCRIPT_DIR"

# Phase 3: Render templates with envsubst
info "Rendering templates..."

RENDERED_DIR="$WORK_DIR/rendered"
mkdir -p "$RENDERED_DIR"

# shellcheck disable=SC2016
ENVSUBST_VARS='$GITOPS_REPO_URL $GITHUB_USERNAME $GITHUB_PAT $DOCKERHUB_USERNAME $DOCKERHUB_PAT'

envsubst "$ENVSUBST_VARS" < "$SCRIPT_DIR/argocd/applicationset.yaml" > "$RENDERED_DIR/applicationset.yaml"
envsubst "$ENVSUBST_VARS" < "$SCRIPT_DIR/kargo/project-config.yaml" > "$RENDERED_DIR/project-config.yaml"
envsubst "$ENVSUBST_VARS" < "$SCRIPT_DIR/kargo/promotion-task.yaml" > "$RENDERED_DIR/promotion-task.yaml"

cp "$SCRIPT_DIR/kargo/warehouse.yaml" "$RENDERED_DIR/warehouse.yaml"
cp "$SCRIPT_DIR/kargo/stages.yaml" "$RENDERED_DIR/stages.yaml"
ok "Templates rendered"

# Phase 4: Apply resources in dependency order
info "Creating Argo CD ApplicationSet..."
kubectl apply -f "$RENDERED_DIR/applicationset.yaml"
ok "ApplicationSet created"

info "Creating Kargo Project..."
kubectl apply -f "$SCRIPT_DIR/kargo/project.yaml"
ok "Project created"

info "Waiting for kargo-demo namespace..."
for _ in $(seq 1 30); do
  if kubectl get namespace kargo-demo &>/dev/null; then
    break
  fi
  sleep 2
done
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/kargo-demo --timeout=60s
ok "Namespace kargo-demo is active"

info "Creating ProjectConfig and credentials..."
kubectl apply -f "$RENDERED_DIR/project-config.yaml"
ok "ProjectConfig and credentials created"

info "Creating Warehouse..."
kubectl apply -f "$RENDERED_DIR/warehouse.yaml"
ok "Warehouse created"

info "Creating PromotionTask..."
kubectl apply -f "$RENDERED_DIR/promotion-task.yaml"
ok "PromotionTask created"

info "Creating Stages (test, uat, prod)..."
kubectl apply -f "$RENDERED_DIR/stages.yaml"
ok "Stages created"

echo ""
ok "Demo setup complete!"
echo ""
info "The Warehouse will discover image tags from docker.io/abodeifregistfy/kargodemo matching >=0.1.0."
info "Freight should appear within a few seconds."
echo ""
info "Next steps:"
info "  1. Open the Kargo dashboard and select the 'kargo-demo' project"
info "  2. The 'test' and 'uat' stages will auto-promote new Freight"
info "  3. After 'uat' is healthy and verified, manually promote Freight to 'prod'"
info "  4. To trigger new Freight, push a new git tag (e.g. v0.3.0) to build a new image"
echo ""
info "To clean up: ./cleanup.sh"
