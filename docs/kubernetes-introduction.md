# An Introduction to Kubernetes

A companion to the course modules. Where the modules are hands-on and in Dutch, this document
gives you the full picture in one place, in English: what Kubernetes is, why it exists, how it
works inside, and what all those object types are for. Read it once now; come back to it
whenever a module introduces something new.

---

## 1. What problem does Kubernetes solve?

Containers solved *packaging*: an image contains your app, its runtime and its dependencies,
and it runs the same everywhere. But containers alone don't answer the questions you face as
soon as an app matters:

- **Where** does each container run, when you have more than one server?
- **What happens** when a container crashes at 3 a.m.? When a whole server dies?
- **How do you update** to a new version without downtime, and roll back if it breaks?
- **How do containers find each other** when they move around and change IP addresses?
- **How do you scale** from 2 to 20 copies when traffic spikes, and back again?
- **Where do configuration and secrets** come from, per environment?

On a single machine, Compose answers some of these (you saw that in modules 04–07). Across
many machines, with no human watching, you need an **orchestrator**. Kubernetes is the
orchestrator that won.

### A very short history

Google ran its own services on an internal cluster manager called **Borg** for over a decade.
In 2014 it open-sourced a redesign of those ideas as **Kubernetes** (Greek for *helmsman*; the
logo is a ship's wheel). In 2015 it was donated to the newly formed **Cloud Native Computing
Foundation (CNCF)**, part of the Linux Foundation. Within a few years every major cloud offered
managed Kubernetes, and competing orchestrators (Docker Swarm, Mesos) faded.

The abbreviation **k8s** is a *numeronym*: k, then 8 letters, then s.

### What Kubernetes is not

- **Not a container runtime.** It doesn't run containers itself; it tells a runtime
  (containerd or CRI-O) on each node what to run.
- **Not a build tool.** It runs images; something else (your CI pipeline) builds them.
- **Not a PaaS.** It gives you building blocks, not a finished platform. Platform teams build
  the platform *on top of* Kubernetes.
- **Not always the right answer.** For one app on one server, Compose is simpler. Kubernetes
  pays off when you have many apps, many machines, many teams, or strict uptime needs.

---

## 2. The core idea: declarative desired state

Everything in Kubernetes follows one idea. Once you understand it, the rest is details.

**Imperative** (what you did with Podman): you issue commands.

```
podman run snip-api      # "start this"
podman stop snip-api     # "stop that"
```

**Declarative** (Kubernetes): you describe the state you want, and the system makes it so.

```yaml
kind: Deployment
spec:
  replicas: 3          # "there should always be three of these"
```

You hand this description to the cluster with `kubectl apply`. From then on, **controllers**
inside the cluster continuously compare the *desired state* with the *actual state*, and act
to close any gap:

```
          ┌────────────────────────────┐
          │ desired: 3 × snip-api      │ ◄── you write this (YAML in Git)
          └─────────────┬──────────────┘
                        │ observe
                        ▼
          ┌────────────────────────────┐
          │ actual:  2 × snip-api      │ ◄── one crashed, or its node died
          └─────────────┬──────────────┘
                        │ diff → act: start 1
                        ▼
                   (repeat forever)
```

This is the **reconciliation loop**, and it is why Kubernetes is called *self-healing*.
Nobody has to notice the crash; the loop does.

Two consequences you'll feel every day:

1. **`kubectl apply` is idempotent.** Applying the same file twice changes nothing the second
   time (`unchanged`). You describe *what*, not *do this now*.
2. **You rarely touch individual containers.** You change the description; the controllers
   change the containers. Deleting a pod managed by a Deployment just makes the Deployment
   create a new one.

This is also why GitOps (Argo CD, part 3 of the course) fits Kubernetes so naturally: if the
desired state is a set of files, you can keep those files in Git and let a tool keep the
cluster in sync with them.

---

## 3. Architecture

A Kubernetes **cluster** is a set of machines (**nodes**) plus a **control plane** that
manages them.

```
              kubectl / CI / Argo CD
                        │  HTTPS (REST + watch)
┌───────────────────────▼───────────────────── control plane ─────────────────┐
│  kube-apiserver        the only entry point; validates and stores objects   │
│  etcd                  consistent key-value store: the cluster's database   │
│  kube-scheduler        picks a node for every new pod                       │
│  kube-controller-manager  runs the built-in reconciliation loops            │
│  cloud-controller-manager (managed clusters) talks to the cloud provider    │
└───────────────┬─────────────────────────┬──────────────────────┬────────────┘
                │ watch                   │                      │
┌───────────────▼───────┐   ┌─────────────▼─────────┐   ┌────────▼──────────────┐
│ node                  │   │ node                  │   │ node                  │
│  kubelet              │   │  kubelet              │   │  kubelet              │
│  container runtime    │   │  container runtime    │   │  container runtime    │
│  kube-proxy           │   │  kube-proxy           │   │  kube-proxy           │
│  pods…                │   │  pods…                │   │  pods…                │
└───────────────────────┘   └───────────────────────┘   └───────────────────────┘
```

### Control plane components

| Component | Role |
|---|---|
| **kube-apiserver** | The front door. Every client (kubectl, controllers, kubelets) talks *only* to the API server. It authenticates, authorizes, validates, and stores objects in etcd. Nothing talks to etcd directly. |
| **etcd** | A distributed, strongly consistent key-value store. Holds every object: desired state and reported status. Back it up, and the cluster can be rebuilt. |
| **kube-scheduler** | Watches for pods without a node, and assigns each to a node based on resource requests, constraints (affinity, taints/tolerations) and spread. It only *decides*; the kubelet *executes*. |
| **kube-controller-manager** | A single binary running dozens of controllers: Deployment, ReplicaSet, Node, Job, EndpointSlice, ServiceAccount… each a reconciliation loop for one kind of object. |
| **cloud-controller-manager** | On cloud clusters: creates load balancers for Services, attaches disks, manages node lifecycle with the cloud API. |

### Node components

| Component | Role |
|---|---|
| **kubelet** | The agent on every node. Watches the API server for pods assigned to its node, tells the runtime to start their containers, runs health probes, and reports status back. |
| **container runtime** | Actually runs containers, via the Container Runtime Interface (CRI). Usually **containerd** or **CRI-O**. (Docker Engine support was removed in 1.24; images built with Docker or Podman run fine, since they're all OCI images.) |
| **kube-proxy** | Programs the node's networking (iptables, IPVS or nftables rules) so that traffic to a Service reaches one of its pods. Some network plugins replace it entirely. |
| **CNI plugin** | Not a single component but a plugin (Calico, Cilium, Azure CNI, kindnet…) that gives each pod an IP address and connects pods across nodes. |

### What happens when you apply a Deployment

A concrete walk-through ties the pieces together:

1. You run `kubectl apply -f deployment.yaml`. kubectl sends the object to the **API server**.
2. The API server authenticates you, checks your permissions (RBAC), runs **admission
   controllers** (policies that can reject or modify the object), and stores it in **etcd**.
3. The **Deployment controller** (in the controller manager) sees a new Deployment and creates a
   **ReplicaSet** for it.
4. The **ReplicaSet controller** sees it needs 3 pods and has 0, so it creates 3 **Pod** objects.
   They have no node yet.
5. The **scheduler** sees 3 unscheduled pods and assigns each to a node.
6. The **kubelet** on each chosen node sees a pod assigned to it, asks the **container runtime** to
   pull the image and start the containers, and the **CNI plugin** gives the pod an IP.
7. The kubelet runs the **readiness probe**. When it passes, the pod is marked *Ready*.
8. The **EndpointSlice controller** adds the ready pod's IP to the Service, and **kube-proxy** on
   every node updates its rules. Traffic now flows to the new pod.

Notice that no component tells another what to do directly. Each one **watches** the API server
for objects it cares about and reacts. That loose coupling is why Kubernetes is so extensible.

`kubectl describe pod` shows this journey in its **Events**: `Scheduled`, `Pulling`, `Pulled`,
`Created`, `Started`.

---

## 4. Objects: the vocabulary

Everything in Kubernetes is an **object** (also called a *resource*) stored in the API: a pod,
a service, a secret. Each object has the same shape:

```yaml
apiVersion: apps/v1          # which API group and version defines this kind
kind: Deployment             # what type of object
metadata:
  name: snip-api             # unique within its namespace and kind
  namespace: snip            # which namespace (default: "default")
  labels:                    # key-value tags used for selection
    app: snip-api
spec:                        # desired state: what YOU want
  ...
status:                      # actual state: what the CLUSTER reports (read-only)
  ...
```

`spec` versus `status` is the declarative model in miniature.

### Labels and selectors

**Labels** are arbitrary key-value pairs on objects. **Selectors** are queries over labels.
Most relationships in Kubernetes are not hard references but label selectors:

- a Deployment manages the pods whose labels match its selector;
- a Service sends traffic to the pods whose labels match its selector;
- a NetworkPolicy applies to the pods whose labels match its selector.

```yaml
# Service: "send traffic to any pod labelled app=snip-api"
spec:
  selector:
    app: snip-api
```

This is powerful and also a classic source of bugs: a typo in a label means a Service silently
selects zero pods.

### Namespaces

A **namespace** is a scope for names, permissions and quotas inside one cluster. Two teams can
each have a Service called `api` in their own namespace. Platform teams typically give each
team (or each team-environment pair) its own namespaces. Some objects, like Nodes and
PersistentVolumes, are cluster-wide and have no namespace.

### Workloads: what runs

| Object | Use it for | Notes |
|---|---|---|
| **Pod** | The smallest unit: one or more containers sharing network (`localhost`, one IP) and optionally volumes, always on the same node. | You almost never create pods directly; controllers do. Pods are disposable and get new IPs when replaced. |
| **ReplicaSet** | Keeps N identical pods running. | Managed by Deployments; you rarely touch it. |
| **Deployment** | Stateless apps (APIs, web frontends). Manages ReplicaSets to provide **rolling updates** and **rollbacks**. | The workhorse. `snip-api` and `snip-web` will be Deployments. |
| **StatefulSet** | Stateful apps (databases, queues) that need stable names (`db-0`, `db-1`), stable storage per replica, and ordered startup. | `snip-db` will be a StatefulSet. In enterprises, databases are often managed services instead. |
| **DaemonSet** | One pod on every node (or every matching node). | Log collectors, monitoring agents, network plugins. |
| **Job** | Run something to completion, with retries. | Database migrations, one-off tasks. |
| **CronJob** | Run a Job on a schedule. | Nightly backups, cleanups. |

A pod can also have **init containers** (run to completion before the app starts, e.g. wait for
a database) and **sidecar containers** (run alongside the app for its whole lifetime, e.g. a
log shipper or proxy).

### Networking: how traffic finds pods

Kubernetes has a simple, strict **network model**:

- every pod gets its own IP address;
- every pod can reach every other pod directly, without NAT, across nodes;
- (and then NetworkPolicies can restrict that).

Pod IPs change whenever pods are replaced, so you never use them directly. Instead:

| Object | What it gives you |
|---|---|
| **Service** | A stable virtual IP and **DNS name** in front of a changing set of pods (selected by labels), with load balancing between them. |
| ↳ `ClusterIP` (default) | Reachable only inside the cluster. `snip-db` will be one: `postgres://…@snip-db:5432`. |
| ↳ `NodePort` | Opens the same port on every node. Mostly for testing. |
| ↳ `LoadBalancer` | Asks the cloud for an external load balancer with a public IP. |
| ↳ headless (`clusterIP: None`) | No virtual IP; DNS returns pod IPs directly. Used with StatefulSets. |
| **Ingress** | HTTP(S) routing from outside: host names and paths to Services, with TLS. Needs an *ingress controller* to do the actual work. |
| **Gateway API** | The successor to Ingress: more expressive (traffic splitting, header matching, TCP/gRPC), with a clear split between platform-owned **Gateways** and app-owned **HTTPRoutes**. |
| **NetworkPolicy** | Firewall rules between pods: "only `snip-api` may talk to `snip-db` on 5432". Enforced by the CNI plugin. |

**DNS**: CoreDNS gives every Service a name. Inside the same namespace you can use the short
name (`snip-db`); from elsewhere the full form is `snip-db.<namespace>.svc.cluster.local`. This is
the cluster-wide version of the Compose/Podman network DNS you used in modules 02 and 04.

> **Note (2026):** the most widely used ingress controller, *ingress-nginx*, was retired by the
> Kubernetes project in March 2026. New setups use Gateway API implementations (Envoy-based
> gateways, Traefik, Istio, or cloud offerings like the AKS application routing gateway). The
> Ingress API itself still exists and is still on the CKAD exam.

### Configuration

| Object | For |
|---|---|
| **ConfigMap** | Non-secret configuration: key-value pairs or whole files. Injected as environment variables or mounted as files. |
| **Secret** | Sensitive values: passwords, tokens, certificates. Same mechanics as ConfigMaps. **Base64-encoded, not encrypted** by default; anyone who can read Secrets in the namespace can read them. Clusters can enable encryption at rest, and enterprises usually source secrets from a vault (Azure Key Vault via the External Secrets Operator or the Secrets Store CSI driver). |

The rule from module 03 still applies: **one image, configured per environment**. The image is
identical in dev and prod; ConfigMaps and Secrets differ.

### Storage

Containers are disposable, so their filesystems are too. For data that must survive:

| Object | Role |
|---|---|
| **PersistentVolume (PV)** | A piece of real storage (an Azure Disk, an NFS share, a local directory). Cluster-wide. |
| **PersistentVolumeClaim (PVC)** | A request for storage by an app: "I need 10 GiB, read-write by one node". Namespaced. |
| **StorageClass** | A recipe for creating PVs on demand (*dynamic provisioning*): "managed-csi = Azure Premium SSD". |

The app asks (PVC), the StorageClass provisions (PV), and the pod mounts the claim. You never
need to know which disk you got. This is the cluster version of the named volume `snip-data`
from module 02. Also the same caveat: deleting the claim can delete the data, depending on
the reclaim policy.

### Health and resources

| Field | Purpose |
|---|---|
| **livenessProbe** | "Is this container alive?" If it fails repeatedly, the kubelet **restarts** the container. snip uses `/health`. |
| **readinessProbe** | "Can it take traffic right now?" If it fails, the pod is **removed from Service endpoints** (not restarted). snip uses `/health/db`. |
| **startupProbe** | Gives slow-starting apps time before liveness checks begin. |
| **resources.requests** | What the container is guaranteed; the scheduler uses this to place pods. |
| **resources.limits** | The maximum. Exceeding the memory limit gets the container killed (`OOMKilled`); CPU is throttled. |

And for scaling:

| Object | Role |
|---|---|
| **HorizontalPodAutoscaler (HPA)** | Changes a Deployment's replica count based on CPU, memory, or custom metrics. |
| **Cluster autoscaler / node autoprovisioning** | Adds or removes *nodes* when pods can't be scheduled or nodes sit idle (cloud clusters). |
| **PodDisruptionBudget (PDB)** | "Never take down more than one `snip-api` pod at a time during maintenance." |

### Identity and access

| Object | Role |
|---|---|
| **ServiceAccount** | An identity for pods, so apps can talk to the API server, or (with workload identity) to Azure. |
| **Role / ClusterRole** | A set of permissions: verbs (`get`, `list`, `create`…) on resources. |
| **RoleBinding / ClusterRoleBinding** | Grants a role to a user, group, or ServiceAccount. |

On AKS, human users authenticate with Microsoft Entra ID, and their group memberships map to
RBAC roles. That's why at work you might be able to `get pods` in your namespace but not
`delete` them, or not see other teams' namespaces at all.

Two more objects round out multi-tenancy: **ResourceQuota** (caps total CPU/memory/objects per
namespace) and **LimitRange** (default requests/limits for pods that don't set them).

---

## 5. Rolling updates and rollbacks

When you change a Deployment's pod template (say, a new image tag), the Deployment creates a
**new ReplicaSet** and gradually shifts pods to it:

```
 v1 ReplicaSet: ●●●            v2 ReplicaSet:
 v1 ReplicaSet: ●●●            v2 ReplicaSet: ○          (new pod starting)
 v1 ReplicaSet: ●●             v2 ReplicaSet: ●          (new pod ready → old one removed)
 v1 ReplicaSet: ●              v2 ReplicaSet: ●●
 v1 ReplicaSet:                v2 ReplicaSet: ●●●        done
```

`maxSurge` and `maxUnavailable` control the pace. **Readiness probes** are what make this safe:
an old pod is only removed when a new one is ready. If the new version never becomes ready, the
rollout stalls and the old pods keep serving traffic.

The old ReplicaSet is kept (scaled to zero), so `kubectl rollout undo` can switch back
instantly. In a GitOps setup you'd instead revert the commit, and Argo CD rolls back.

During shutdown, each old pod receives **SIGTERM**, has a grace period (30 s by default) to
finish in-flight requests, and then gets SIGKILL. This is why the graceful-shutdown handler
from module 05 matters.

---

## 6. Talking to the cluster: kubectl

`kubectl` is a client for the API server. Which cluster it talks to is determined by the current
**context** in `~/.kube/config` (cluster address + credentials + default namespace).

```bash
kubectl config get-contexts               # which clusters do I know? (* = current)
kubectl config use-context kind-snip      # switch

kubectl get pods                          # list (in the current namespace)
kubectl get pods -A                       # all namespaces
kubectl get deploy,svc,pods -n snip       # several kinds, in namespace "snip"
kubectl describe pod <name>               # details + Events (start here when debugging)
kubectl logs <pod> [-c container] [--previous] [-f]
kubectl exec -it <pod> -- sh
kubectl port-forward svc/snip-web 8080:80 # temporary tunnel from your machine

kubectl apply -f k8s/                     # create/update everything in a folder
kubectl delete -f k8s/
kubectl diff -f k8s/                      # what would apply change?

kubectl rollout status deploy/snip-api
kubectl rollout undo deploy/snip-api

kubectl explain deployment.spec.strategy  # built-in reference docs
kubectl create deployment x --image=y --dry-run=client -o yaml   # generate YAML
```

A debugging habit worth building early, from the outside in:

1. `kubectl get pods`: what's the status? (`Pending`, `ImagePullBackOff`, `CrashLoopBackOff`,
   `Running` but not `Ready`?)
2. `kubectl describe pod`: what do the **Events** say?
3. `kubectl logs [--previous]`: what did the app say before it died?
4. `kubectl get endpointslices` / `describe svc`: does the Service actually select any pods?

| Status | Usually means |
|---|---|
| `Pending` | No node has room (requests too high), or a PVC can't be bound. |
| `ImagePullBackOff` / `ErrImagePull` | Wrong image name/tag, private registry without credentials, or no image for the node's architecture. |
| `CrashLoopBackOff` | The container starts and exits, over and over. Check `logs --previous`. |
| `Running`, `0/1 Ready` | Readiness probe failing: the app is up but not ready (e.g. can't reach its database). |
| `OOMKilled` | Exceeded its memory limit. |
| `CreateContainerConfigError` | A referenced ConfigMap or Secret (or key) doesn't exist. |

---

## 7. The ecosystem around it

Kubernetes is deliberately a core plus extension points. The most important ones:

**Custom Resources and Operators.** You can teach the API server new kinds of objects with a
**CustomResourceDefinition (CRD)**, and write a controller that reconciles them. An **operator** is
such a controller with domain knowledge: a Postgres operator that turns a `PostgresCluster`
object into a replicated, backed-up database. Argo CD itself is configured through CRDs
(`Application`, `AppProject`).

**Packaging and templating.** Raw YAML gets repetitive across environments.
- **Kustomize** (built into kubectl as `kubectl apply -k`): a base set of manifests plus
  per-environment *overlays* that patch them. No templating language.
- **Helm**: a package manager. A *chart* is a set of templated manifests plus a `values.yaml`; you
  install it with different values per environment. Most third-party software ships as a Helm
  chart.

**GitOps.** **Argo CD** and **Flux** run inside the cluster, watch a Git repository, and keep the
cluster in sync with it. This turns the reconciliation idea up one level: Git is the desired
state for the *whole cluster*. Deploys become pull requests; rollbacks become reverts; drift is
detected and corrected automatically.

**Policy.** **Kyverno** and **OPA Gatekeeper** act as admission controllers: "reject any pod
running as root", "require resource limits", "only images from our registry". On AKS, Azure
Policy builds on Gatekeeper.

**Observability.** **Prometheus** (metrics) and **Grafana** (dashboards), **OpenTelemetry** for
traces, and log pipelines (Loki, Azure Monitor/Container Insights).

**Certificates.** **cert-manager** requests and renews TLS certificates (for example from Let's
Encrypt) for your Ingresses and Gateways: Caddy's automatic HTTPS from module 07, done the
Kubernetes way.

**Service mesh.** Istio, Linkerd, Cilium: mutual TLS between services, fine-grained traffic
control, and telemetry, without changing app code.

---

## 8. Flavours of Kubernetes

Kubernetes is a specification with a conformance test suite. Many distributions pass it:

| Flavour | Who runs the control plane | Typical use | In this course |
|---|---|---|---|
| **kind** | You, in a container | Local development, CI tests | modules 08–18 |
| **minikube** | You, in a VM or container | Local development | (alternative to kind) |
| **k3s** | You; a single lightweight binary | Small servers, edge, homelabs | module 19, on your droplet |
| **AKS / EKS / GKE** | The cloud provider (managed) | Production | modules 20–21 (AKS) |
| **OpenShift, Rancher, Tanzu** | Vendor-supported platforms | Enterprises wanting a full platform | — |

Your manifests are portable across all of them. What differs is the *edges*: load balancers,
storage classes, identity, and which add-ons come pre-installed.

---

## 9. When (not) to use Kubernetes

**Good fit:**
- many services and teams sharing infrastructure;
- you need zero-downtime deploys, self-healing, and autoscaling;
- you want one standard way to deploy everything, with GitOps, policy, and observability on top.

**Probably overkill:**
- one small app, one server, a single team: Compose (module 06) or a PaaS is simpler;
- you have no one to own the platform. Kubernetes moves complexity; it doesn't remove it.
  Managed offerings (AKS) and platform teams exist precisely to absorb that complexity so app
  teams don't have to.

---

## 10. How snip will map onto Kubernetes

| snip piece | Compose (module 04/06) | Kubernetes (part 2 onwards) |
|---|---|---|
| API | service `api`, `image: ghcr.io/…/snip-api` | **Deployment** `snip-api` + **Service** `snip-api` |
| Database | service `db`, volume `db-data` | **StatefulSet** `snip-db` + **PVC** + headless **Service** |
| Web (nginx) | service `web`, bind mounts | **Deployment** `snip-web` + **ConfigMap** for `nginx.conf` and the page |
| Password | `.env` | **Secret** (later: from Key Vault) |
| Front door + HTTPS | Caddy, ports 80/443 | **Gateway/Ingress** + **cert-manager** |
| Health | `healthcheck` | **liveness/readiness probes** on `/health` and `/health/db` |
| `depends_on` | yes | **doesn't exist**: apps must tolerate dependencies being temporarily unavailable |
| Restart on reboot | `restart: unless-stopped` | built in: the reconciliation loop |
| Deploy | `docker compose up -d` via SSH (push) | Argo CD syncs from Git (pull) |

---

## 11. Glossary

| Term | Meaning |
|---|---|
| **Cluster** | Control plane + nodes, managed as one system. |
| **Node** | A machine (VM or physical) that runs pods. |
| **Control plane** | API server, etcd, scheduler, controllers: the cluster's brain. |
| **Pod** | One or more containers sharing network and storage; the unit of scheduling. |
| **Workload** | Something that runs pods: Deployment, StatefulSet, DaemonSet, Job, CronJob. |
| **Controller** | A loop that reconciles desired state with actual state for one kind of object. |
| **Manifest** | A YAML (or JSON) file describing one or more objects. |
| **Label / selector** | Key-value tag / query over tags; how objects find each other. |
| **Namespace** | A scope for names, access control and quotas within a cluster. |
| **Service** | Stable name and virtual IP in front of a set of pods. |
| **Ingress / Gateway** | HTTP(S) entry from outside the cluster to Services. |
| **ConfigMap / Secret** | Configuration / sensitive configuration, injected into pods. |
| **PV / PVC / StorageClass** | Storage / a request for storage / a recipe for creating storage. |
| **Probe** | A health check the kubelet runs (liveness, readiness, startup). |
| **Requests / limits** | Guaranteed / maximum CPU and memory for a container. |
| **RBAC** | Role-based access control: who may do what to which resources. |
| **CRD / Operator** | A new object type / a controller that manages it with domain knowledge. |
| **Context** | A kubeconfig entry: which cluster, which user, which default namespace. |
| **Reconciliation** | Continuously making actual state match desired state. |
| **GitOps** | Using Git as the desired state for the cluster, synced by a tool like Argo CD. |

---

## 12. Further reading

- **Official documentation:** <https://kubernetes.io/docs/>. The *Concepts* section is excellent
  and pairs well with this document.
- **kubectl reference / cheat sheet:** <https://kubernetes.io/docs/reference/kubectl/quick-reference/>
- **The CKAD curriculum** (what the exam covers): <https://github.com/cncf/curriculum>
- **Gateway API:** <https://gateway-api.sigs.k8s.io/>
- **Argo CD:** <https://argo-cd.readthedocs.io/>
- **kind:** <https://kind.sigs.k8s.io/>

During the CKAD exam you may use `kubernetes.io/docs`, so getting comfortable navigating it now
pays off later.
