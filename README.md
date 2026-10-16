# Kargo Demo

A hands-on demonstration of progressive, GitOps-driven delivery using
**Kargo**, **Argo CD**, **Argo Rollouts**, and **Helm**. A small nginx app is
promoted through three environments — **test → uat → prod** — with
auto-promotion for the lower environments and a manual approval gate for
production.

---

## Purpose of the Demo

This repo shows how to build a complete promotion pipeline where **both
application changes and configuration changes flow through the same governed
path to production**:

- **Kargo** watches for new artifacts (a new container image tag *or* a Helm
  chart change on `main`), bundles them into immutable **Freight**, and
  promotes that Freight stage by stage.
- Each promotion renders the Helm chart for that stage and writes it to a
  dedicated `stage/<name>` Git branch.
- **Argo CD** keeps each environment continuously in sync with its stage
  branch.
- **Argo Rollouts** performs a canary rollout within each environment, running
  an HTTP health check before shifting all traffic.

The running app displays the stage name, version, and pod hostname, so you can
*see* which version is live in each environment as Freight is promoted.

```
 image tag (v*)                commit to main under app/
      │                                   │
      └────────────┬──────────────────────┘
                   ▼
           ┌───────────────┐
           │   Warehouse   │  creates one Freight bundling both artifacts
           └───────┬───────┘
                   ▼
   ┌───────────┐  auto   ┌───────────┐  auto   ┌───────────┐  manual
   │   test    │ ──────▶ │    uat    │ ──────▶ │   prod    │
   │ 1 replica │         │ 2 replicas│         │ 3 replicas│
   └─────┬─────┘         └─────┬─────┘         └─────┬─────┘
         │ render Helm         │ render Helm         │ render Helm
         │ → stage/test        │ → stage/uat         │ → stage/prod
         ▼                     ▼                     ▼
   ┌───────────┐         ┌───────────┐         ┌───────────┐
   │ Argo CD   │         │ Argo CD   │         │ Argo CD   │
   │ app (sync)│         │ app (sync)│         │ app (sync)│
   └─────┬─────┘         └─────┬─────┘         └─────┬─────┘
         ▼                     ▼                     ▼
  kargo-demo-test       kargo-demo-uat        kargo-demo-prod
  namespace             namespace             namespace
```

---

## Prerequisites

Before running the demo you need:

| Requirement | Why |
|-------------|-----|
| A Kubernetes cluster | Target for all three environments |
| **Kargo** installed in the cluster | Drives the promotion pipeline |
| **Argo CD** installed in the cluster | Syncs each stage branch to its namespace |
| **Argo Rollouts** installed in the cluster | Runs the canary rollout and health check |
| `kubectl`, configured for the cluster | Applies the manifests |
| `git`, `envsubst` available locally | Used by `setup.sh` |
| A GitHub repo (this repo) | Serves as both source and GitOps target |
| A DockerHub repo | Stores the container images |
| GitHub PAT — *Contents: Read and write* | Lets Kargo push rendered manifests |
| DockerHub access token — *Read & Write* | Lets CI push images |

Set the following environment variables (used by `setup.sh`):

```bash
export GITOPS_REPO_URL=https://github.com/<username>/<repo>
export GITHUB_USERNAME=<username>
export GITHUB_PAT=<github-personal-access-token>
export DOCKERHUB_USERNAME=<dockerhub-username>
export DOCKERHUB_PAT=<dockerhub-access-token>
```

> Tip: keep these in an untracked `.env` file and `source .env`. The repo's
> `.gitignore` already excludes `.env`.

---

## Setup Steps

Run the full setup with a single command:

```bash
./setup.sh
```

The script performs the steps below, in order. Each step and its expected
output is described so you know what "working" looks like.

### Step 1 — Validate prerequisites

**What it does:** Confirms the five environment variables are set, that
`kubectl`, `git`, and `envsubst` are on `PATH`, and that it can reach the
cluster.

**Expected output:**

```
[INFO]  Checking prerequisites...
[OK]    Prerequisites verified
```

If a variable is missing or the cluster is unreachable, the script prints a
`[ERROR]` line and exits without changing anything.

### Step 2 — Initialize the GitOps repository

**What it does:** Clones the GitOps repo and, if it does not already contain the
Helm chart, copies `app/` in and pushes it to `main`.

**Expected output:**

```
[INFO]  Initializing GitOps repository at https://github.com/<user>/<repo>...
[OK]    Helm chart pushed to https://github.com/<user>/<repo>
```

(If the chart is already present, you'll see a "skipping push" message instead —
that's fine.)

### Step 3 — Render templates

**What it does:** Runs `envsubst` on `argocd/applicationset.yaml`,
`kargo/project-config.yaml`, and `kargo/promotion-task.yaml` to substitute your
repo URL, username, and credentials.

**Expected output:**

```
[INFO]  Rendering templates...
[OK]    Templates rendered
```

### Step 4 — Create the Argo CD ApplicationSet

**What it does:** Applies the ApplicationSet, which generates three Argo CD
Applications — `kargo-demo-test`, `kargo-demo-uat`, `kargo-demo-prod` — each
tracking its own `stage/<name>` branch with auto-sync enabled.

**Expected output:**

```
[INFO]  Creating Argo CD ApplicationSet...
[OK]    ApplicationSet created
```

**Verify:**

```bash
kubectl get applications -n argocd
# NAME              SYNC STATUS   HEALTH STATUS
# kargo-demo-test   ...           ...
# kargo-demo-uat    ...           ...
# kargo-demo-prod   ...           ...
```

The apps may show `Unknown`/`Missing` until the first promotion populates the
stage branches — that is expected at this point.

### Step 5 — Create the Kargo Project

**What it does:** Applies the `Project`, which creates the `kargo-demo`
namespace and establishes the Kargo project scope.

**Expected output:**

```
[INFO]  Creating Kargo Project...
[OK]    Project created
[INFO]  Waiting for kargo-demo namespace...
[OK]    Namespace kargo-demo is active
```

### Step 6 — Create the ProjectConfig and credentials

**What it does:** Applies the auto-promotion policy (test and uat auto-promote)
and the Git and image credential Secrets.

**Expected output:**

```
[INFO]  Creating ProjectConfig and credentials...
[OK]    ProjectConfig and credentials created
```

### Step 7 — Create the Warehouse

**What it does:** Applies the Warehouse, which subscribes to two artifact
sources: new image tags, and commits to `main` that touch `app/`.

**Expected output:**

```
[INFO]  Creating Warehouse...
[OK]    Warehouse created
```

**Verify:** within a few seconds the Warehouse discovers artifacts and creates
Freight:

```bash
kubectl get warehouse kargo-demo -n kargo-demo
kubectl get freight -n kargo-demo
# A Freight entry (random ALIAS) should appear, origin Warehouse kargo-demo
```

### Step 8 — Create the PromotionTask

**What it does:** Applies the reusable 7-step promotion process that every Stage
runs (see [Promotion Steps](#promotion-steps)).

**Expected output:**

```
[INFO]  Creating PromotionTask...
[OK]    PromotionTask created
```

### Step 9 — Create the Stages

**What it does:** Applies the three Stages (`test`, `uat`, `prod`) that form the
pipeline. `test` draws Freight directly from the Warehouse, `uat` from `test`,
and `prod` from `uat`.

**Expected output:**

```
[INFO]  Creating Stages (test, uat, prod)...
[OK]    Stages created

[OK]    Demo setup complete!
```

**Verify the pipeline runs:** test and uat auto-promote, so within a minute or
two they should become `Healthy`:

```bash
kubectl get stages -n kargo-demo
# NAME   CURRENT FREIGHT   HEALTH    ...
# test   <freight>         Healthy
# uat    <freight>         Healthy
# prod   <freight>         Healthy / <none>
```

```bash
# Confirm each environment is actually running
kubectl get pods,svc,rollout -n kargo-demo-test
kubectl get pods,svc,rollout -n kargo-demo-uat
```

---

## Promotion Steps

When Freight is promoted to a Stage, the `demo-promo-process` PromotionTask runs
these steps (`kargo/promotion-task.yaml`):

| # | Step | What it does |
|---|------|--------------|
| 1 | `git-clone` | Checks out the exact `main` commit carried by the Freight into `./src`, and the stage branch `stage/<name>` into `./out`. Using the Freight's commit (not branch HEAD) keeps promotions deterministic across stages |
| 2 | `git-clear` | Wipes `./out` so the stage branch is rebuilt from a clean slate (no stale files) |
| 3 | `copy` | Copies the Helm chart from `./src/app` into `./out/app` |
| 4 | `yaml-update` | Sets `image.tag` in `./out/app/values-<stage>.yaml` to the image tag from the Freight |
| 5 | `git-commit` | Commits the updated chart on the stage branch |
| 6 | `git-push` | Pushes the stage branch to the GitOps repo |
| 7 | `argocd-update` | Tells Argo CD to sync the stage's Application to the exact commit just pushed |

Argo CD then renders the Helm chart (`path: app`, with `values-<stage>.yaml`)
and applies it. Argo Rollouts drives the canary steps and runs the
`http-health-check` AnalysisTemplate before promoting to full traffic.

---

## Promoting Freight

**Auto-promotion (test and uat):** New Freight is promoted to `test`
automatically. Once `test` is healthy, the same Freight auto-promotes to `uat`.

**Manual promotion (prod):** After `uat` is healthy, open the Kargo dashboard
(or use the CLI) and manually promote the Freight to `prod`.

---

## Triggering a New Promotion

Freight is created by **either** of these:

**A new image (application change):**

```bash
# edit index.html / Dockerfile, then tag a release
git add . && git commit -m "update app"
git tag v0.3.0
git push origin main v0.3.0
```

CI builds and pushes `abodeifregistfy/kargodemo:0.3.0`; the Warehouse discovers
the new tag and creates Freight.

**A Helm chart change (configuration change):**

```bash
# edit anything under app/ (replicas, resources, probes, templates...)
git add app/ && git commit -m "bump test replicas"
git push origin main
```

The Warehouse's Git subscription watches `main` under `app/`, so the commit
creates Freight too. Either way, Freight auto-promotes through test and uat and
waits for manual approval at prod.

---

## Per-Stage Differences

Each stage renders the chart with its own values file, producing real
differences you can observe in the cluster:

| Stage | Replicas | CPU (req/limit) | Memory (req/limit) | Canary strategy |
|-------|----------|-----------------|--------------------|-----------------|
| test  | 1 | 50m / 100m | 32Mi / 64Mi | 20% → full |
| uat   | 2 | 100m / 200m | 64Mi / 128Mi | 25% → analysis → full |
| prod  | 3 | 200m / 500m | 128Mi / 256Mi | 10% → 50% → analysis → full |

---

## Cleanup

```bash
./cleanup.sh
```

This deletes the Kargo Project (cascading to all resources in the `kargo-demo`
namespace), the Argo CD ApplicationSet, and the three stage namespaces. The
GitOps repository branches are left untouched — remove `stage/*` branches
manually if you want a completely clean slate.

---

## Repository Layout

```
├── Dockerfile                     # Unprivileged nginx image (non-root, read-only rootfs)
├── default.conf                   # nginx server config (serves /tmp/html on :8080)
├── index.html                     # App template (rendered with envsubst at startup)
├── start.sh                       # Renders the page, then starts nginx
├── .github/workflows/
│   ├── ci.yaml                    # Lint, Helm validate, Trivy security scan, test build
│   └── build-and-push.yaml        # Build, Trivy-scan, and push image on a v* tag
├── app/                           # Helm chart (pushed to the GitOps repo)
│   ├── Chart.yaml
│   ├── values.yaml                # Base defaults + security context
│   ├── values-test.yaml           # test: 1 replica
│   ├── values-uat.yaml            # uat: 2 replicas
│   ├── values-prod.yaml           # prod: 3 replicas
│   └── templates/
│       ├── _helpers.tpl           # Name, label, selector helpers
│       ├── configmap.yaml         # STAGE_NAME, APP_VERSION env
│       ├── deployment.yaml        # Deployment (used when rollout disabled)
│       ├── rollout.yaml           # Argo Rollouts canary (used when rollout enabled)
│       ├── service.yaml           # Stable ClusterIP Service
│       ├── service-canary.yaml    # Canary Service for the rollout
│       └── analysis-template.yaml # HTTP health check used by the canary
├── argocd/
│   └── applicationset.yaml        # Generates the three Argo CD Applications
├── kargo/
│   ├── project.yaml               # Kargo Project (creates the namespace)
│   ├── project-config.yaml        # Auto-promotion policy + credentials
│   ├── warehouse.yaml             # Image + Git (chart) subscriptions
│   ├── promotion-task.yaml        # 7-step Helm-based promotion process
│   ├── analysis-template.yaml     # Standalone AnalysisTemplate (project scope)
│   └── stages.yaml                # test, uat, prod Stages
├── setup.sh                       # One-command setup
└── cleanup.sh                     # Teardown
```
