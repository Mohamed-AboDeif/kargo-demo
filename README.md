# Kargo Demo

A 3-stage promotion pipeline powered by **Kargo** and **Argo CD**, demonstrating
continuous delivery of a Helm-based application through test, uat, and prod
environments with auto-promotion and per-stage configuration.

## Architecture Overview

```
┌──────────┐    v* tag     ┌───────────┐  push image  ┌───────────┐
│ GitHub   │──────────────▶│  CI/CD    │─────────────▶│ DockerHub │
│ (source) │               │ (Actions) │              │ (registry)│
└──────────┘               └───────────┘              └─────┬─────┘
                                                            │
                                                   discovers new tag
                                                            │
                                                    ┌───────▼───────┐
                                                    │   Warehouse   │
                                                    │ (watches tags │
                                                    │  >=0.1.0)     │
                                                    └──────┬────────┘
                                                           │
                                                   creates Freight
                                                           │
                          ┌────────────────────────────────┼──────────────────┐
                          │                                │                  │
                  ┌───────▼───────┐               ┌────────▼────────┐  ┌──────▼──────┐
                  │  test Stage   │──────────────▶│   uat Stage     │─▶│ prod Stage  │
                  │  (auto)       │  auto-promote │   (auto)        │  │ (manual)    │
                  │  1 replica    │               │   2 replicas    │  │ 3 replicas  │
                  └───────┬───────┘               └────────┬────────┘  └──────┬──────┘
                          │                                │                  │
                   renders Helm                     renders Helm        renders Helm
                   + pushes to                      + pushes to         + pushes to
                   stage/test branch                stage/uat branch    stage/prod branch
                          │                                │                  │
                  ┌───────▼───────┐               ┌────────▼────────┐  ┌──────▼──────┐
                  │  Argo CD App  │               │  Argo CD App    │  │ Argo CD App │
                  │  kargo-demo-  │               │  kargo-demo-    │  │ kargo-demo- │
                  │  test         │               │  uat            │  │ prod        │
                  │  (auto-sync)  │               │  (auto-sync)    │  │ (auto-sync) │
                  └───────┬───────┘               └────────┬────────┘  └──────┬──────┘
                          │                                │                  │
                          ▼                                ▼                  ▼
                   kargo-demo-test               kargo-demo-uat        kargo-demo-prod
                   namespace                     namespace             namespace
```

## Components

### Kargo Resources

| Resource | File | Purpose |
|----------|------|---------|
| **Project** | `kargo/project.yaml` | Creates the `kargo-demo` namespace and establishes the Kargo project scope |
| **ProjectConfig** | `kargo/project-config.yaml` | Configures auto-promotion policies for test and uat stages, and stores Git/DockerHub credentials as Secrets |
| **Warehouse** | `kargo/warehouse.yaml` | Subscribes to two artifact sources: (1) image tags on `docker.io/abodeifregistfy/kargodemo` matching `>=0.1.0`, and (2) commits to `main` that touch `app/` (the Helm chart). A new image tag **or** a chart change creates Freight, so both flow through the test → uat → prod pipeline |
| **PromotionTask** | `kargo/promotion-task.yaml` | Defines the 7-step process that runs each time Freight is promoted to a Stage (see [Promotion Steps](#promotion-steps) below) |
| **Stages** | `kargo/stages.yaml` | Three Stages forming the pipeline: **test** receives Freight directly from the Warehouse, **uat** receives from test, **prod** receives from uat |
| **AnalysisTemplate** | `kargo/analysis-template.yaml` | *(Optional, requires Argo Rollouts)* HTTP health check that verifies the app is responding after promotion |

### Argo CD Resources

| Resource | File | Purpose |
|----------|------|---------|
| **ApplicationSet** | `argocd/applicationset.yaml` | Generates 3 Argo CD Applications (one per stage) using a list generator. Each Application tracks a `stage/<name>` branch with `directory.recurse: true` and auto-sync enabled |

### Helm Chart (`app/`)

| File | Purpose |
|------|---------|
| `Chart.yaml` | Chart metadata (name: `kargo-demo`, version: `0.1.0`) |
| `values.yaml` | Base defaults: image, replicas, service config, probe settings |
| `values-test.yaml` | Test overrides: 1 replica, stage name "test", small resource limits |
| `values-uat.yaml` | UAT overrides: 2 replicas, stage name "uat", medium resource limits |
| `values-prod.yaml` | Prod overrides: 3 replicas, stage name "prod", larger resource limits |
| `templates/deployment.yaml` | Deployment with liveness/readiness probes and env vars from ConfigMap |
| `templates/service.yaml` | ClusterIP Service exposing port 80 |
| `templates/configmap.yaml` | ConfigMap injecting `STAGE_NAME` and `APP_VERSION` as environment variables |
| `templates/_helpers.tpl` | Helm helpers for resource naming and standard Kubernetes labels |

### Application

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds nginx:1.27-alpine with the HTML template and startup script |
| `index.html` | HTML template with `${STAGE_NAME}`, `${APP_VERSION}`, and `${HOSTNAME}` placeholders |
| `start.sh` | Runs `envsubst` to render the HTML template at container startup, then starts nginx |

### CI/CD Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yaml` | Push/PR to main | Runs yamllint on YAML files, shellcheck on scripts, `helm lint` + `helm template` per stage, and tests the Docker build |
| `build-and-push.yaml` | Push of `v*` tag | Builds the Docker image and pushes it to DockerHub as `abodeifregistfy/kargodemo:<version>` and `latest` |

## Promotion Steps

When Freight is promoted to a Stage, the `demo-promo-process` PromotionTask executes these 7 steps:

| Step | Built-in Action | What It Does |
|------|----------------|--------------|
| 1 | `git-clone` | Clones the GitOps repo twice: the `main` branch into `./src` (source of truth with Helm chart) and the `stage/<name>` branch into `./out` (target for rendered manifests) |
| 2 | `git-clear` | Wipes `./out` so the stage branch gets a clean set of rendered manifests (no stale files) |
| 3 | `yaml-update` | Patches `image.tag` in `./src/app/values-<stage>.yaml` with the new image tag from the Freight |
| 4 | `helm-template` | Runs `helm template` on the chart at `./src/app` using the stage-specific values file, writing fully rendered Kubernetes manifests into `./out` |
| 5 | `git-commit` | Commits the rendered manifests in `./out` with a message like "Promote test to image tag 0.3.0" |
| 6 | `git-push` | Pushes `./out` to the `stage/<name>` branch on the remote GitOps repo |
| 7 | `argocd-update` | Tells Argo CD to sync the corresponding Application to the exact commit, deploying the new manifests to the cluster |

## Per-Stage Differences

Each stage renders the Helm chart with its own values file, producing real configuration differences:

| Stage | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-------|----------|-------------|-----------|----------------|-------------|
| test  | 1        | 50m         | 100m      | 32Mi           | 64Mi        |
| uat   | 2        | 100m        | 200m      | 64Mi           | 128Mi       |
| prod  | 3        | 200m        | 500m      | 128Mi          | 256Mi       |

The app page dynamically displays the stage name, version, and pod hostname so
you can visually confirm which stage and version you are viewing.

## Prerequisites

- Kubernetes cluster with **Kargo** and **Argo CD** installed
- `kubectl` configured to access the cluster
- `git` and `envsubst` available locally
- A GitHub repository (this repo) for both source code and GitOps manifests
- A DockerHub repository for container images
- GitHub PAT with **Contents: Read and write** on this repo
- DockerHub access token with **Read & Write** permission

**Optional:** Install **Argo Rollouts** to enable post-promotion verification
via the included AnalysisTemplate (`kargo/analysis-template.yaml`). Without
Argo Rollouts, the pipeline works but skips verification — add the
`verification` block to each Stage in `kargo/stages.yaml` once installed.

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
export GITOPS_REPO_URL=https://github.com/<username>/<repo>
export GITHUB_USERNAME=<username>
export GITHUB_PAT=<personal-access-token>
export DOCKERHUB_USERNAME=<dockerhub-username>
export DOCKERHUB_PAT=<dockerhub-access-token>

./setup.sh
```

The setup script will:

1. Push the Helm chart (`app/`) to the GitOps repository
2. Create an Argo CD ApplicationSet (3 Applications with auto-sync)
3. Create the Kargo Project (triggers namespace creation)
4. Create the ProjectConfig (auto-promotion policies) and credential Secrets
5. Create the Warehouse (starts watching DockerHub for tags)
6. Create the PromotionTask (7-step Helm-based promotion process)
7. Create the 3 Stages (test, uat, prod — forming the promotion pipeline)

## Promoting Freight

After setup, the Warehouse discovers image tags and produces Freight.

**Auto-promotion (test and uat):**

New Freight is automatically promoted to the **test** stage. Once test is
healthy, the same Freight auto-promotes to **uat**.

**Manual promotion (prod):**

After uat is healthy, open the Kargo dashboard and manually promote the
Freight to **prod**.

## Releasing a New Version

To trigger a new promotion cycle:

```bash
# Make changes to index.html or Dockerfile
git add . && git commit -m "update app"
git tag v0.3.0
git push origin main v0.3.0
```

The CI workflow builds and pushes `abodeifregistfy/kargodemo:0.3.0`.
Kargo discovers the new tag, creates new Freight, and auto-promotes
through test and uat. Manually approve for prod.

## Cleanup

```bash
./cleanup.sh
```

This deletes the Kargo Project (which cascades to all resources in the
`kargo-demo` namespace), the Argo CD ApplicationSet, and the three
stage namespaces (`kargo-demo-test`, `kargo-demo-uat`, `kargo-demo-prod`).
The GitOps repository branches are not modified.

## File Structure

```
├── Dockerfile                     # App image (nginx + dynamic index.html)
├── index.html                     # App template (envsubst at startup)
├── start.sh                       # Nginx startup with envsubst
├── .github/workflows/
│   ├── ci.yaml                    # Lint, Helm validate, test build
│   └── build-and-push.yaml        # Build & push on tag (v*)
├── app/                           # Helm chart (pushed to GitOps repo)
│   ├── Chart.yaml
│   ├── values.yaml                # Base defaults
│   ├── values-test.yaml           # Test: 1 replica, small resources
│   ├── values-uat.yaml            # UAT: 2 replicas, medium resources
│   ├── values-prod.yaml           # Prod: 3 replicas, larger resources
│   └── templates/
│       ├── _helpers.tpl           # Name, labels, selector helpers
│       ├── configmap.yaml         # Stage metadata (STAGE_NAME, APP_VERSION)
│       ├── deployment.yaml        # Deployment with probes and env
│       └── service.yaml           # ClusterIP Service
├── argocd/
│   └── applicationset.yaml        # Argo CD ApplicationSet (auto-sync)
├── kargo/
│   ├── project.yaml               # Kargo Project (creates namespace)
│   ├── project-config.yaml        # ProjectConfig + credentials + auto-promotion
│   ├── warehouse.yaml             # Watches DockerHub for new tags
│   ├── promotion-task.yaml        # 7-step Helm-based promotion process
│   ├── analysis-template.yaml     # HTTP health check (requires Argo Rollouts)
│   └── stages.yaml                # test, uat, prod Stages
├── setup.sh                       # One-command setup
└── cleanup.sh                     # Teardown
```
