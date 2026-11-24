# DSO202 Assignment 4


This repository runs my Task Tracker app (frontend, backend and PostgreSQL) on a kind cluster using Argo CD. Argo CD checks this repo every 60 seconds and makes the cluster match what is written here. Nothing is deployed by hand after the first setup.

There are two environments:

| | dev | staging |
|---|---|---|
| Namespace | `dso202-dev` | `dso202-staging` |
| Follows | branch `main` | a tag (`v1.0.0`, `v1.1.0`, `v1.2.0`) |
| Sync | automatic, with prune and self heal | manual |
| Open at | http://localhost:30080 | port forward to http://localhost:8081 |

Dev gets every change straight away. Staging only changes when I move its tag and sync it myself.

## Folders

| Folder | What it holds |
|---|---|
| `cluster/` | kind cluster config |
| `bootstrap/` | Argo CD install, the platform project and the root app (applied by hand once) |
| `argocd/` | the dso202 project and all child Applications (managed by the root app) |
| `platform/` | namespaces, quota, limits, RBAC and sealed credentials for each environment |
| `charts/tasktracker/` | the Helm chart, same for both environments |
| `environments/` | values that differ between dev and staging |
| `docs/evidence.md` | command output for every task |

## Versions

| Tool | Version |
|---|---|
| Argo CD and argocd CLI | v3.5.6 |
| Sealed Secrets chart | 2.20.0 |
| Sealed Secrets controller and kubeseal | 0.40.0 |
| kind, kubectl | same as Practical 1 |
| Helm | same as Assignment 3 |
| App images | tags 1.0 and 1.1 from the tutor |
| Smoke test | `busybox:1.37` |

## Rebuild everything from scratch

You need Docker with at least 6 GB of memory, the tools above, and the sealing key backup saved in `../dso202-keys/`.

```bash
git clone https://github.com/<github-username>/dso202-gitops.git
cd dso202-gitops

kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml

# put the sealing key back before the controller starts
kubectl create namespace sealed-secrets
kubectl apply -f ../dso202-keys/sealing-key.backup.yaml

# install Argo CD
kubectl apply -k bootstrap/argocd --server-side --force-conflicts
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s

# start the root app, which brings up everything else
kubectl apply -f bootstrap/root
kubectl get applications -n argocd -w

# log in (run the port forward in a separate terminal) and sync staging
kubectl port-forward svc/argocd-server -n argocd 8080:443
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
argocd app sync tasktracker-staging
```

Staging frontend:

```bash
kubectl port-forward -n dso202-staging svc/tasktracker-frontend 8081:80
```

## Cleanup

```bash
kind delete cluster --name dso202-gitops
```

Keep the key backup, because you need it to rebuild. Be careful with the root app: deleting it removes every app and workload with it.

## How secrets are handled

The database username and password are only stored in Git as SealedSecrets, one file for dev and one for staging, each with a different password. I created them by piping `kubectl create secret --dry-run=client` straight into `kubeseal`, so no plain Secret file was ever saved. The plain input files were in `secrets-plain/`, which Git ignores, and I deleted them after sealing. The controller inside the cluster turns each SealedSecret back into a normal Secret called `tasktracker-credentials`, and the chart reads that name. The private sealing key is backed up outside the repo with permission 600. A search of the whole Git history finds none of the real values.

## Answers

### Q1

The root app belongs to the platform project, so that project has to exist before the root can be created. That is why I apply it by hand. It also has admin level access, so I do not want the root app managing its own permissions. The dso202 project is just a normal limit for the app, so it lives in Git and the root creates it.

If dso202 could deploy into the argocd namespace, someone could commit an Application there that uses the platform project. That Application could then deploy anything anywhere in the cluster, or change Argo CD's own settings. In other words, the app project would get admin rights.

### Q2

Strict scope locks a SealedSecret to its name and namespace. You cannot copy it into another namespace or rename it and still decrypt it. This stops someone moving the dev secret to a place where they can read it, and it is why dev and staging are sealed separately.

If the key is lost, the Secrets already running keep working, but every SealedSecret in Git becomes useless on a new cluster. I would have to seal every secret again from the original values in my password manager and commit the new files. If those values were also lost, I would have to change the database passwords. If the key was leaked instead, every secret sealed with it should be treated as exposed and changed.

### Q3

Synced means the cluster matches what Git says. Healthy means the things in the cluster are actually working. They are separate checks.

Example from Task 7:

```text
<paste argocd app get tasktracker-dev output here>
```

When I changed the backend to 1.1, Argo CD applied it exactly as written, so the app was Synced. But the new Pod could not start, and after 120 seconds the Deployment was marked Degraded. So it was Synced but not Healthy.

### Q4

Argo CD RBAC controls what people can do inside Argo CD, like viewing apps, syncing, or reading logs. It is set in `argocd-rbac-cm`. Kubernetes RBAC controls what users and service accounts can do directly in the cluster. It is set with Role and RoleBinding objects, which are in `platform/<env>/rbac.yaml`. Argo CD makes changes using its own service account, so what an Argo CD user can do depends on Argo CD RBAC and the project, not on their own Kubernetes access.

With SSO, I would remove the local reviewer account and give permissions to a role instead. Groups from the login provider would then be linked to that role, like this:

```text
p, role:dso202-reviewer, applications, get, dso202/*, allow
p, role:dso202-reviewer, logs, get, dso202/*, allow
g, <idp-group-name>, role:dso202-reviewer
```

Who can do what would then be managed in the login provider instead of in Argo CD.

### Q5

Rollback is refused because dev has automatic sync. A rollback would put the cluster on an old version while Git still points to the new one, and auto sync would undo it straight away. In GitOps, the fix has to happen in Git.

So the GitOps way is `git revert`. It makes a new commit that undoes the bad one, and Argo CD applies it. I prefer it to deleting the commit because it keeps the full history of what happened, it does not break anyone else's copy of the repo or any tags, and it goes through a normal pull request like any other change.

### Q6 (a)

Good things about one repo:

1. A change to the chart and its values can go in one commit, so one tag covers both.
2. It is simple. There is one URL, one place to look, and one clone to rebuild from.

Bad things about one repo:

1. Anyone who can change the chart can also change staging promotion and the Argo CD apps.
2. Every commit, even a small one, is part of the same history and the same tags, so release tags can include unrelated changes.

### Q6 (b)

| Not under GitOps | How teams usually handle it |
|---|---|
| Argo CD install (`bootstrap/argocd`) | Let Argo CD manage itself, or install it with Terraform. |
| Platform project and root app | Created by the same setup automation as the cluster. |
| Sealing key | Kept in a secure vault or secrets manager. |
| Database data | Regular backups and tested restores, or a managed database. |
| The cluster itself | Created with infrastructure as code, like Terraform. |
| Admin and reviewer passwords | Replaced by SSO login. |
| Syncing staging | Kept manual on purpose, as an approval step. |