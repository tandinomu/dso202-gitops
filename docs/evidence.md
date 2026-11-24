<!--
=============================================================================
File        : docs/evidence.md
Assignment  : DSO202 Assignment 4
Purpose     : Command output proving every task. Each item shows the command
              that was run and its output. Replace every <paste ...> block.
              Never paste a credential value or the sealing key.
=============================================================================
-->

# Evidence — DSO202 Assignment 4

Repository: https://github.com/<github-username>/dso202-gitops.git

---

## Task 1 — Repository, chart contract and cluster

### Tool check (section 3.2)

```text
$ docker version --format '{{.Server.Version}}'
<paste>
$ kind version
<paste>
$ kubectl version --client
<paste>
$ helm version --short
<paste>
$ git --version
<paste>
$ argocd version --client
<paste>
$ kubeseal --version
<paste>
$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
<paste: must list 2.20.0>
```

### Chart contract

| # | Requirement | Where it is satisfied |
|---|---|---|
| C1 | Image repository and tag are values | `values.yaml`: `<tier>.image.repository`; `environments/<env>/values.yaml`: `<tier>.image.tag`; templates use `required` so no tag is written in a template |
| C2 | Per-tier configuration from values | `values.yaml`: `database.env`, `backend.env`, `frontend.env` → ConfigMaps in `templates/{database,backend,frontend}.yaml`, loaded with `envFrom` |
| C3 | No Secret rendered; `existingSecret` | `values.yaml` and both env files: `existingSecret: tasktracker-credentials`; `secretKeyRef` in `database.yaml`, `backend.yaml` |
| C4 | Readiness probes on all tiers | `database.yaml` (`pg_isready`), `backend.yaml` (`GET backend.readinessPath` = `/api/status`), `frontend.yaml` (`GET /`) |
| C5 | Sync waves 0 / 1 / 2 | `argocd.argoproj.io/sync-wave` on StatefulSet (`database.yaml`) "0", backend Deployment "1", frontend Deployment "2" |
| C6 | `progressDeadlineSeconds: 120` | `values.yaml`: `rollout.progressDeadlineSeconds`; used in `backend.yaml` and `frontend.yaml` |
| C7 | Requests and limits on every container | `values.yaml`: `<tier>.resources`; smoke test has its own in `smoke-test-job.yaml` |
| C8 | No Namespace/Quota/LimitRange/Role/RoleBinding | Chart renders only Deployment, StatefulSet, Service, ConfigMap, ServiceAccount, Job (see kind list below); those objects live in `platform/<env>/` |
| C9 | Ingress disabled by default | The chart has no Ingress template |
| C10 | Frontend NodePort, port as value | `frontend.service.type: NodePort`; `frontend.service.nodePort` 30080 (dev) / 30081 (staging) |
| C11 | `helm lint` clean, `helm template` works | Output below |

```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
<paste>
$ helm lint charts/tasktracker -f environments/staging/values.yaml
<paste>
$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort | uniq -c
<paste>
```

### Cluster

```text
$ kubectl config current-context
<paste>
$ kubectl get nodes
<paste>
$ docker ps --filter name=dso202-gitops --format '{{.Names}}   {{.Ports}}'
<paste: must show 30080>
```

---

## Task 2 — Install Argo CD declaratively

```text
$ kubectl kustomize bootstrap/argocd | grep -E '^kind: (Deployment|StatefulSet)$' | sort | uniq -c
<paste: 6 Deployment, 1 StatefulSet>
$ kubectl kustomize bootstrap/argocd | grep 'image:' | sort -u
<paste>
$ kubectl get pods -n argocd
<paste: 7 Running>
$ kubectl get crd | grep argoproj.io
<paste>
$ kubectl get configmap argocd-cm -n argocd -o yaml | grep -E 'timeout.reconciliation|accounts.reviewer'
<paste>
$ argocd version
<paste>
```

Screenshot: Argo CD UI after sign-in → `docs/img/task2-ui.png` <!-- add the file and link it -->

---

## Task 3 — AppProjects and the root Application

Whitelist check: the kinds from Task 1 (Deployment, StatefulSet, Service,
ConfigMap, ServiceAccount, Job) equal the `namespaceResourceWhitelist` in
`argocd/projects/dso202.yaml`. No additions were needed.

```text
$ kubectl get appproject,application -n argocd
<paste>
$ argocd app get root
<paste: dso202 AppProject listed among root's resources>
$ argocd proj get dso202
<paste>
```

Screenshot: root resource tree → `docs/img/task3-root-tree.png`

---

## Task 4 — Platform layer and Sealed Secrets

```text
$ kubectl get applications -n argocd
<paste>
$ kubectl get pods -n sealed-secrets
<paste>
$ kubectl get crd sealedsecrets.bitnami.com
<paste>
$ ls -l ../dso202-keys/
<paste: file name, -rw------- permissions; NEVER the contents>
$ kubectl get namespaces | grep dso202
<paste>
$ kubectl get sealedsecret -n dso202-dev
<paste>
$ kubectl describe secret tasktracker-credentials -n dso202-dev
<paste: key names and sizes only>
$ kubectl describe secret tasktracker-credentials -n dso202-staging
<paste>
$ kubectl get resourcequota,limitrange -n dso202-dev
<paste>
```

No plaintext in history. Keys tested (values not recorded): dev DB_USER,
dev DB_PASSWORD, staging DB_USER, staging DB_PASSWORD
(POSTGRES_* carry the same values).

```text
$ git log -p --all -S'<value>' | head      # run once per value; each printed nothing
<paste: empty output for each>
$ git status --short --ignored
<paste>
```

---

## Task 5 — Workloads in dev and staging

```text
$ kubectl get pods -n dso202-dev -w
<paste: database Ready before backend created, backend Ready before frontend>
$ kubectl get job -n dso202-dev
<paste>
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
<paste>
$ argocd app get tasktracker-dev
<paste>
```

CRUD cycle in dev (http://localhost:30080): <describe create / read / update / delete, or screenshots>

```text
$ argocd app get root          # before the first staging sync
<paste: Progressing>
$ argocd app get tasktracker-staging
<paste: OutOfSync / Missing>
$ argocd app sync tasktracker-staging
<paste>
$ argocd app get root          # after
<paste: Healthy>
$ kubectl get applications -n argocd
<paste: all Synced and Healthy>
```

Screenshot: tasktracker-dev resource tree → `docs/img/task5-dev-tree.png`

---

## Task 6 — Access control

```text
$ argocd account list
<paste>
$ argocd --argocd-context reviewer app list
<paste: only tasktracker-dev, tasktracker-staging>
$ argocd --argocd-context reviewer account can-i get applications 'dso202/tasktracker-dev'
yes
$ argocd --argocd-context reviewer account can-i sync applications 'dso202/tasktracker-dev'
no
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
no
$ argocd --argocd-context reviewer proj get platform
<paste: permission denied>
```

After the logs rule (commit <sha>):

```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
<paste>
$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
yes
```

Screenshot: reviewer session showing Pod logs → `docs/img/task6-reviewer-logs.png`

---

## Task 7 — Release, faulty release, recovery

Pull requests:

| # | Title |
|---|---|
| <n> | Release frontend 1.1 |
| <n> | Promote staging to v1.1.0 |
| <n> | Release backend 1.1 |
| <n> | Revert "Release backend 1.1" |
| <n> | Fix forward: backend 1.1 with <VARIABLE> |
| <n> | Promote staging to v1.2.0 |

```text
$ git log --oneline --graph --decorate -n 15
<paste>
```

### Part A

```text
$ argocd app history tasktracker-dev
<paste>
$ argocd app get tasktracker-staging        # after the targetRevision PR, before sync
<paste: OutOfSync>
$ argocd app sync tasktracker-staging
<paste>
```

### Part B

Bad commit: `<sha>`

Observations (step 5): new backend Pod: <state>; old backend Pod: <state>;
Application: <sync> / <health>; smoke test ran: <yes/no>; frontend responds: <yes/no>.

```text
$ kubectl get pods -n dso202-dev
<paste>
$ kubectl describe pod <new-backend-pod> -n dso202-dev
<paste relevant part>
$ kubectl logs <new-backend-pod> -n dso202-dev
<paste>
```

Log line stating the requirement: `<exact line>`

```text
$ argocd app rollback tasktracker-dev
<paste the refusal>
```

After revert (step 8), fix-forward (step 9) and promotion (step 10):

```text
$ argocd app get tasktracker-dev
<paste>
$ argocd app history tasktracker-dev
<paste>
$ argocd app history tasktracker-staging
<paste: no revision with the faulty backend>
```

---

## Task 8 — Drift, pruning and project guardrails

### Drill 1 — Drift in dev

Prediction: <one sentence>

```text
<commands and output>
```

Result: <held / did not hold, and why: selfHeal: true in tasktracker-dev>

### Drill 2 — Drift in staging

Prediction: <one sentence>

```text
<commands and output, including argocd app diff>
```

Result: <...: no automated block, so drift is reported as OutOfSync but not reverted>

### Drill 3 — Pruning

Prediction: <one sentence>

```text
<commands and output: ConfigMap present, then NotFound>
```

Result: <...: prune: true in platform-dev. Namespace manifest carries Prune=false, so deleting namespace.yaml would not delete the namespace>

### Drill 4 — Project guardrail

Prediction: <one sentence>

```text
<commands and output: the exact "not permitted in project" message>
```

Result: <...: ResourceQuota absent from namespaceResourceWhitelist; staging unaffected because it reads tag v1.2.0, which does not contain the file>

---

## Task 9 — Rebuild from Git

```text
$ date
<start>
$ git rev-parse HEAD
<paste>
$ kubectl get applications -n argocd        # before
<paste>
... every command of steps 2-8 with output ...
$ date
<end>
```

Order in which Applications became Healthy: <...>
Elapsed time from `kind create cluster` to working dev frontend: <mm:ss>

---

## Task 10 — Bonus: multi-source Application

```text
$ argocd app get tasktracker-dev
<paste: two sources, Synced, Healthy>
```

When separating sources is useful: <one paragraph>
