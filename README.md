# Kargo Demo

A 3-stage promotion pipeline powered by Kargo, demonstrating continuous
promotion of a custom Docker image through test, uat, and prod environments.

```
Push tag v0.2.0 → CI builds image → DockerHub → Kargo Warehouse discovers tag
→ Freight created → promote: test → uat → prod
```

## Prerequisites

- Kubernetes cluster with **Kargo** and **Argo CD** installed
- `kubectl` configured to access the cluster
- `git` and `envsubst` available locally
- A GitHub repository (this repo) for both source code and GitOps manifests
- A DockerHub repository for container images
- GitHub PAT with **Contents: Read and write** on this repo
- DockerHub access token with **Read & Write** permission

## Setup

### 1. Configure GitHub Secrets

The CI workflow needs DockerHub credentials to push images:

```bash
gh secret set DOCKERHUB_USERNAME
gh secret set DOCKERHUB_TOKEN
```

### 2. Build and Push the Initial Image

Before Kargo can discover any Freight, at least one tagged image must exist:

```bash
docker login
docker build -t abodeifregistfy/kargodemo:0.1.0 .
docker push abodeifregistfy/kargodemo:0.1.0
```

Or push a git tag to trigger the CI workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

### 3. Deploy to Kubernetes

```bash
export GITOPS_REPO_URL=https://github.com/Mohamed-AboDeif/kargo-demo
export GITHUB_USERNAME=Mohamed-AboDeif
export GITHUB_PAT=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
export DOCKERHUB_USERNAME=abodeifregistfy
export DOCKERHUB_PAT=dckr_pat__oaLN1V9jyDSh6zKfspvi-zuLGA

./setup.sh
```

The setup script will:

1. Push the Kustomize app manifests (`app/`) to the GitOps repository
2. Create an Argo CD ApplicationSet (3 Applications: test, uat, prod)
3. Create a Kargo Project with Git and DockerHub credentials
4. Create a Warehouse watching `docker.io/abodeifregistfy/kargodemo`
5. Create a PromotionTask and 3 Stages

## Promoting Freight

After setup, the Warehouse discovers image tags and produces Freight.

**Using the Kargo Dashboard:**

1. Open the dashboard and select the `kargo-demo` project
2. Drag a piece of Freight onto the **test** Stage
3. Wait for **test** to become healthy
4. Promote the same Freight to **uat**, then **prod**

## Releasing a New Version

To trigger a new promotion cycle:

```bash
# Make changes to index.html or Dockerfile
git add . && git commit -m "update app"
git tag v0.2.0
git push origin main v0.2.0
```

The CI workflow builds and pushes `abodeifregistfy/kargodemo:0.2.0`.
Kargo discovers the new tag and creates new Freight.

## Cleanup

```bash
./cleanup.sh
```

## File Structure

```
├── Dockerfile                 # App image (nginx + custom index.html)
├── index.html                 # App content
├── .github/workflows/
│   ├── ci.yaml                # Lint, validate, test build
│   └── build-and-push.yaml    # Build & push on tag (v*)
├── app/                       # Kustomize manifests (pushed to GitOps branches)
│   ├── base/
│   │   ├── kustomization.yaml
│   │   └── deployment.yaml
│   └── stages/{test,uat,prod}/
│       └── kustomization.yaml
├── argocd/
│   └── applicationset.yaml    # Argo CD ApplicationSet
├── kargo/
│   ├── project.yaml           # Project + Git/DockerHub credentials
│   ├── warehouse.yaml         # Watches DockerHub for new tags
│   ├── promotion-task.yaml    # 7-step promotion process
│   └── stages.yaml            # test, uat, prod Stages
├── setup.sh                   # One-command setup
└── cleanup.sh                 # Teardown
```
