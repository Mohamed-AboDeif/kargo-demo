#!/usr/bin/env bash
set -euo pipefail

info()  { printf '\033[0;34m[INFO]\033[0m  %s\n' "$1"; }
ok()    { printf '\033[0;32m[OK]\033[0m    %s\n' "$1"; }

info "Deleting Kargo Project (cascades to all resources in kargo-demo namespace)..."
kubectl delete project kargo-demo --ignore-not-found

info "Deleting Argo CD ApplicationSet..."
kubectl delete applicationset kargo-demo -n argocd --ignore-not-found

info "Deleting stage namespaces..."
for ns in kargo-demo-dev kargo-demo-stg kargo-demo-prd; do
  kubectl delete namespace "$ns" --ignore-not-found
done

ok "Demo resources cleaned up."
info "Note: The GitOps repository was not modified. Clean up branches manually if desired."
