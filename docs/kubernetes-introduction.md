# An Introduction to Kubernetes

This is a companion to the course modules, written to be read aloud. The modules are hands-on and in Dutch. This document is in English and gives you the full picture in one go: what Kubernetes is, why it exists, how it works on the inside, and what all those object types are for. Listen to it once now, and come back to it whenever a module introduces something new.

## 1. What problem does Kubernetes solve?

Containers solved packaging. An image holds your app, its runtime and its dependencies, and it runs the same everywhere. But containers alone don't answer the questions you face as soon as an app starts to matter.

Where does each container run, when you have more than one server? What happens when a container crashes at three in the morning, or when a whole server dies? How do you update to a new version without downtime, and roll back if it breaks? How do containers find each other when they keep moving around and changing IP addresses? How do you go from two copies to twenty when traffic spikes, and back again? And where do configuration and secrets come from, for each environment?

On a single machine, Compose answers some of these questions. You saw that in modules four to seven. But across many machines, with no human watching, you need an orchestrator. Kubernetes is the orchestrator that won.

### A very short history

For more than a decade, Google ran its own services on an internal cluster manager called Borg. In 2014 it open-sourced a redesign of those ideas and called it Kubernetes. That's Greek for helmsman, the person who steers a ship, which is why the logo is a ship's wheel. In 2015 Google donated it to the newly formed Cloud Native Computing Foundation, the CNCF, which is part of the Linux Foundation. Within a few years every major cloud offered managed Kubernetes, and competing orchestrators like Docker Swarm and Mesos faded away.

You'll often see Kubernetes written as k8s. That's a numeronym: the letter k, then eight letters, then the letter s.

### What Kubernetes is not

Kubernetes is not a container runtime. It doesn't run containers itself. It tells a runtime on each machine, usually containerd, what to run.

It is not a build tool either. It runs images, and something else, like your CI pipeline, builds them.

It is not a finished platform. It gives you building blocks, and platform teams build the platform on top of it.

And it is not always the right answer. For one app on one server, Compose is simpler. Kubernetes pays off when you have many apps, many machines, many teams, or strict uptime requirements.

## 2. The core idea: declarative desired state

Everything in Kubernetes follows one idea. Once you understand it, the rest is details.

With Podman, you worked imperatively. You gave commands: start this, stop that.

Kubernetes is declarative. Instead of giving commands, you describe the state you want, and the system makes it so. You write down, for example: there should always be three copies of the snip API. You hand that description to the cluster, and from then on, small programs inside the cluster called controllers keep comparing what you asked for with what actually exists. If they see a gap, they act to close it.

Say one of the three copies crashes, or the machine it ran on dies. The controller notices that there are two instead of three, and starts a new one. Then it checks again, and again, forever. This is called the reconciliation loop, and it is why Kubernetes is called self-healing. Nobody has to notice the crash. The loop does.

You'll feel two consequences of this every day. First, applying the same description twice changes nothing the second time. You describe what you want, not what to do right now. Second, you rarely touch individual containers. You change the description, and the controllers change the containers. If you delete a pod that belongs to a Deployment, the Deployment simply creates a new one.

This is also why GitOps fits Kubernetes so naturally. If the desired state is a set of files, you can keep those files in Git and let a tool, like Argo CD in part three of the course, keep the cluster in sync with them.

## 3. Architecture

A Kubernetes cluster is a set of machines, called nodes, plus a control plane that manages them.

### The control plane

The control plane is the brain of the cluster. It has a handful of parts.

The API server is the front door. Every client talks only to the API server: your kubectl, your CI pipeline, Argo CD, and even the other parts of Kubernetes itself. The API server checks who you are, checks what you're allowed to do, validates what you send, and stores it.

It stores everything in etcd, a small, very reliable database. etcd holds every object in the cluster: both what you asked for and what the cluster reports back. Back up etcd, and you can rebuild the cluster.

The scheduler watches for new pods that don't have a machine yet, and picks a node for each one, based on how much CPU and memory the pod asks for and on any placement rules. The scheduler only decides. It doesn't start anything.

The controller manager runs dozens of those reconciliation loops: one for Deployments, one for ReplicaSets, one for Jobs, one for nodes, and so on. Each loop looks after one kind of object.

On cloud clusters there's also a cloud controller manager, which talks to the cloud provider to create load balancers, attach disks, and manage machines.

### The nodes

Every node runs an agent called the kubelet. The kubelet watches the API server for pods assigned to its node, tells the container runtime to start their containers, runs their health checks, and reports their status back.

The container runtime does the actual work of running containers. Usually that's containerd. Images you built with Docker or Podman run fine, because they all follow the same open image standard.

Then there's networking. A network plugin gives every pod its own IP address and connects pods across nodes. Cilium and Calico are well-known examples. And kube-proxy, or a network plugin that replaces it, makes sure that traffic sent to a Service ends up at one of its pods.

### What happens when you apply a Deployment

Let's walk through it, because it ties all the pieces together.

You apply a Deployment, and kubectl sends it to the API server. The API server checks who you are and whether you're allowed to do this, runs any policies that might reject or adjust it, and stores it in etcd.

The Deployment controller notices the new Deployment and creates a ReplicaSet for it. The ReplicaSet controller notices it needs three pods and has none, so it creates three pod objects. At this point they don't have a node yet.

The scheduler notices three pods without a node and assigns each to one. The kubelet on each chosen node notices a pod assigned to it, asks the runtime to pull the image and start the container, and the network plugin gives the pod an IP address.

The kubelet then runs the readiness check. When it passes, the pod is marked ready, it gets added behind its Service, and traffic starts to flow to it.

Notice that no part tells another part what to do. Each one watches the API server for the objects it cares about, and reacts. That loose coupling is what makes Kubernetes so easy to extend. When you describe a pod with kubectl, you can see this whole journey in its events: scheduled, pulling, pulled, created, started.

## 4. Objects: the vocabulary

Everything in Kubernetes is an object stored in the API: a pod, a service, a secret. You describe objects in files called manifests. The word comes from a ship's manifest, the list of everything that's supposed to be on board.

Every object has the same shape. It says which API version and which kind it is, it has metadata like a name, a namespace and labels, and then it has two important parts: spec and status. The spec is what you want. The status is what the cluster reports. That pair, spec versus status, is the whole declarative model in miniature.

Manifests are usually written in YAML, although the API itself speaks JSON. YAML is just friendlier for humans: you can write comments, and you don't need all the braces and quotes. A single YAML file can hold several objects, separated by a line of three dashes.

### Labels and selectors

Labels are simple key-value tags you put on objects, like app equals snip-api. Selectors are queries over those labels.

Most relationships in Kubernetes aren't hard links, they're selectors. A Deployment manages the pods whose labels match its selector. A Service sends traffic to the pods whose labels match its selector. A network policy applies to the pods whose labels match its selector.

That's powerful, and it's also a classic source of bugs. A typo in a label, and a Service silently selects zero pods.

### Namespaces

A namespace is a scope inside a cluster for names, permissions and budgets. Two teams can each have a Service called api, each in their own namespace. Platform teams usually give each team, or each combination of team and environment, its own namespaces, like snip-test and snip-prod. A few objects, like nodes, belong to the whole cluster and have no namespace.

### Workloads: what runs

The smallest unit is the pod: one or more containers that share a network and always run together on the same machine. You almost never create pods yourself. Controllers do that for you. Pods are disposable, and they get a new IP address every time they're replaced.

A ReplicaSet keeps a fixed number of identical pods running. You rarely touch one directly, because Deployments manage them for you.

A Deployment is the workhorse, for stateless apps like APIs and web frontends. It manages ReplicaSets to give you rolling updates and rollbacks. The snip API and the snip web frontend are Deployments.

A StatefulSet is for stateful apps like databases. It gives each copy a stable name, like db zero and db one, its own storage, and a fixed start-up order. The snip database is a StatefulSet. In larger companies, databases are often a managed cloud service instead.

A DaemonSet runs one pod on every node, which is handy for log collectors and monitoring agents.

A Job runs something until it's finished, with retries, like a database migration. And a CronJob runs a Job on a schedule, like a nightly backup.

A pod can also have init containers, which run to completion before the app starts, for instance to wait for a database. And it can have sidecar containers, which run next to the app for its whole life, like a log shipper or a proxy.

### Networking: how traffic finds pods

Kubernetes has a simple network model. Every pod gets its own IP address, and every pod can reach every other pod directly, across nodes. Network policies can then restrict that.

Because pod addresses keep changing, you never use them directly. Instead you put a Service in front. A Service is like a customer service phone number: the number stays the same, but who picks up changes. It gives a stable name and address to a changing group of pods, and spreads traffic between them.

By default a Service is only reachable inside the cluster. That's how the API reaches the database, simply by the name snip-db. There are also Services that open a port on every node, mostly for testing, and Services that ask the cloud for a real external load balancer. A headless Service has no shared address at all, and hands out the pod addresses directly. That's used with StatefulSets.

To bring web traffic in from outside, there used to be Ingress. Its successor is the Gateway API, which is more expressive and splits the work cleanly: the platform team owns the Gateway, the front door itself, and app teams own the routes that send traffic to their Services. The most widely used Ingress controller, ingress-nginx, was retired in March 2026, so new setups use Gateway implementations like Envoy Gateway, which is what this course uses.

Network policies are firewall rules between pods, like: only the snip API may talk to the snip database, on the Postgres port. The network plugin enforces them.

Every Service also gets a DNS name. Inside the same namespace, the short name is enough. From another namespace, you add the namespace name. It's the cluster-wide version of the network names you used with Compose.

### Configuration

A ConfigMap holds configuration that isn't secret: settings, or whole files like an nginx configuration. A Secret holds sensitive values like passwords and tokens. Both can be handed to a container as environment variables or as files.

One warning about Secrets: by default they're only encoded, not encrypted. Anyone who's allowed to read Secrets in a namespace can read the passwords. That's why companies usually keep the real secrets in a vault, like Azure Key Vault, and sync them in with a tool like External Secrets.

The rule from module three still applies: one image, configured per environment. The image is identical in test and production. Only the ConfigMaps and Secrets differ.

### Storage

Containers are disposable, and so are their file systems. For data that has to survive, there are three pieces.

A persistent volume claim is the app's request for storage, like: I need ten gigabytes that one node can write to. A storage class is a recipe that creates the actual storage on demand, like an Azure SSD. And the persistent volume is the actual piece of storage that comes out of it.

The app asks, the storage class provides, and the pod mounts the claim. You never need to know which disk you got. It's the cluster version of the named volume from module two, with the same warning: deleting the claim can delete the data.

### Health

The kubelet runs health checks called probes. The liveness probe asks: is this container still alive? If it keeps failing, the container is restarted. The readiness probe asks: can this pod take traffic right now? If it fails, the pod is taken out from behind its Service, but not restarted. Snip uses the health endpoint for liveness, and the database health endpoint for readiness. There's also a startup probe, which gives slow apps some time before the liveness checks begin.

### Resources and budgets

Each container can state requests and limits for CPU and memory. The request is what the container is guaranteed, and the scheduler uses it to decide where the pod fits. The limit is the maximum. A container that goes over its memory limit gets killed, and one that wants more CPU than its limit just gets slowed down.

On the namespace level there are two more objects. A ResourceQuota is the budget for the whole namespace, all pods together. A LimitRange fills in default requests and limits for containers that don't set their own. Think of it like this: the container's resources are what one person spends, the quota is the team budget, and the limit range is the default allowance for anyone who forgot to say.

If a new pod would push the namespace over its quota, it's refused. Not queued, refused.

### Scaling

A HorizontalPodAutoscaler changes a Deployment's number of copies based on how busy the pods are. You don't hard-code the number anymore. You give it a minimum, a maximum and a target, for example: keep the average CPU usage around seventy percent of what the pods requested. If the pods get busier, it adds copies. If they're quiet for a while, it removes some, slowly on purpose, so it doesn't flap up and down. It needs the metrics server to see how busy the pods are, and it needs the pods to have CPU requests, because the percentage is calculated from those.

On cloud clusters, a cluster autoscaler can also add or remove whole machines. And a pod disruption budget makes sure maintenance never takes down too many copies of an app at the same time.

### Identity and access

Kubernetes has two kinds of identities. People, who on Azure log in with Microsoft Entra ID, and machines, which use a ServiceAccount. A pipeline that deploys, or an app that talks to the API, gets its own ServiceAccount. Clouds have the same idea under different names, like a managed identity on Azure, and they can be linked together so no passwords need to be stored at all.

Permissions work through roles. A role is a list of what's allowed: which actions, on which kinds of objects. A role binding gives that role to a person, a group or a ServiceAccount. There are ready-made roles in every cluster, like view, which can only look and can't read Secrets, edit, which can change almost everything in a namespace, and admin. For machines you usually write your own small role, with only what's needed. A deployer, for example, only needs to read and patch Deployments, and look at pods.

One thing that surprises people: the actions in a role aren't kubectl commands. They're the actions of the API, which follow the web's HTTP methods: get, list, watch, create, update, patch and delete. Apply doesn't exist as an action. Applying an existing object is really a get followed by a patch, and applying a new one is a get followed by a create. Roles protect the API, not one particular tool, so that Helm, Argo CD and your own code all play by the same rules.

And if nothing grants you a permission, you don't have it. Without a role binding, a team can't even look inside a namespace.

## 5. Rolling updates and rollbacks

When you change the pod template of a Deployment, for example by giving it a new image tag, the Deployment creates a new ReplicaSet and moves pods over to it step by step. A new pod starts. Once it's ready, an old one is removed. And so on, until all pods run the new version.

Two settings control the pace. Max surge says how many pods may be added on top of the desired number during an update. Max unavailable says how many may be missing. With a surge of one and zero unavailable, Kubernetes always starts one new pod first, and only removes an old one when the new one is ready. That gives you updates without downtime.

These settings are relative to the number of copies at that moment, also when the autoscaler decides that number. So if the autoscaler has scaled to its maximum of six, and you roll out an update with a surge of one, you'll briefly have seven pods. Make sure your cluster and your namespace quota have room for that. If the quota is full, the extra pod is refused, and because no old pod may leave first, the rollout gets stuck.

Readiness probes are what make all this safe. If the new version never becomes ready, the rollout stalls, and the old pods keep serving traffic.

A rollout only happens when the pod template changes. If you apply the same image tag again, like latest, nothing changes in the description, so nothing happens. Kubernetes doesn't go and check whether there's a newer image behind that tag. That's why you use a unique tag per version, like the Git commit.

The old ReplicaSet is kept around with zero pods, so you can roll back instantly. You can add a change-cause note to a Deployment, so the rollout history tells you what each version was. In a GitOps setup you'd simply revert the commit, and Argo CD rolls back.

When an old pod is stopped, it first gets a polite signal to shut down, and thirty seconds by default to finish what it's doing, before it's killed. That's why the graceful shutdown handling from module five matters.

## 6. Talking to the cluster

kubectl is a client for the API server. Which cluster it talks to depends on the current context in your kube config file: a combination of a cluster address, your credentials, and a default namespace.

The commands you'll use all the time are get, to list objects; describe, to see details and events; logs, to read what a container printed; exec, to open a shell inside a container; and apply, to send your manifests to the cluster. There's also diff, to see what apply would change, rollout status, to wait until an update is done, and rollout undo, to go back.

Because everything inside a local cluster is internal by default, you use port forward to open a temporary tunnel from your own machine to a Service. That tunnel only lives as long as the command runs. Close the terminal, and the tunnel is gone.

When something goes wrong, work from the outside in. First, get the pods and look at their status. Then describe the pod and read the events. Then read the logs, including those of the previous crashed run. And finally, check whether the Service actually selects any pods.

A few statuses you'll see a lot. Pending usually means no node has room, or the storage isn't ready. Image pull back-off means a wrong image name or tag, or a private registry without credentials. Crash loop back-off means the container keeps starting and exiting, so read the logs of the previous run. Running but not ready means the readiness probe is failing, for example because the database is unreachable. And OOM killed means the container went over its memory limit.

## 7. The ecosystem around it

Kubernetes itself is deliberately small: pods, services, scheduling. Everything else comes from a large ecosystem around it, most of it under the CNCF.

Custom resources and operators let you teach Kubernetes new kinds of objects. An operator is a controller with expert knowledge. A Postgres operator, for example, can turn one short object describing a database cluster into replicated, backed-up Postgres, by creating the StatefulSets, Services and Secrets for you.

For packaging, there are two tools. Kustomize takes a base set of manifests and patches them per environment, without any templating language. Helm is a package manager. A Helm chart is a blueprint of an app's whole infrastructure: all its manifests with blanks in them, plus a values file to fill in those blanks. The chart doesn't contain the image itself. It points to it. If you wanted to hand snip to ten other people, the image alone wouldn't be enough, they'd also need the Deployments, Services, database, secrets and routes. A chart packages all of that, with a version number, so they can install it, configure it, upgrade it and roll it back. Charts are packages, not boilerplate. You install them, you don't copy them. Most third-party software, like Envoy Gateway, the metrics server or Argo CD, ships as a Helm chart, stored in chart repositories or in the same registries as images. Artifact Hub is the catalogue to search them, a bit like npm for Kubernetes.

GitOps tools like Argo CD and Flux run inside the cluster, watch a Git repository, and keep the cluster in sync with it. It's the reconciliation idea one level up: Git is the desired state for the whole cluster. Deploys become pull requests, rollbacks become reverts, and drift is detected and corrected automatically.

Policy tools like Kyverno check every object before it's accepted, with rules like: no pods running as root, every container needs resource limits, and only images from our own registry.

For observability there's Prometheus for metrics, Grafana for dashboards, OpenTelemetry for traces, and Loki for logs. Cert-manager requests and renews TLS certificates, for example from Let's Encrypt. And service meshes like Istio, Linkerd and Cilium add encrypted traffic between services and fine-grained traffic control, without changing app code.

## 8. Flavours of Kubernetes

Kubernetes is a specification with a test suite, and many distributions pass it.

kind runs a whole cluster inside containers on your laptop, and it's what this course uses from module eight onwards. Minikube is a similar alternative. k3s is a single lightweight program for small servers and homelabs, and you'll run it on your droplet. And then there are the managed clusters from the big clouds, like AKS on Azure, where the cloud provider runs the control plane for you. Vendors like Red Hat with OpenShift sell complete platforms on top.

Your manifests work on all of them. What differs are the edges: load balancers, storage, identity, and which add-ons come pre-installed.

## 9. When, and when not, to use Kubernetes

Kubernetes is a good fit when many services and teams share infrastructure, when you need updates without downtime, self-healing and autoscaling, and when you want one standard way to deploy everything, with GitOps, policy and observability on top.

It's probably overkill for one small app on one server with a single team. Compose or a hosted platform is simpler there. And it's a bad idea when nobody owns the platform. Kubernetes moves complexity, it doesn't remove it. Managed offerings like AKS, and platform teams, exist precisely to absorb that complexity, so app teams don't have to.

## 10. How snip maps onto Kubernetes

In Compose, the snip API was one service. In Kubernetes, it's a Deployment with a Service in front, and an autoscaler that decides how many copies run. The web frontend is also a Deployment, with its nginx configuration and its page coming from ConfigMaps. The database becomes a StatefulSet with its own storage claim and a headless Service. The password moves from an env file to a Secret, and later to Key Vault. Caddy's role as the front door with HTTPS is taken over by the Gateway and cert-manager. The Compose health checks become liveness and readiness probes.

Two things from Compose disappear. Depends on doesn't exist in Kubernetes, so apps must cope with a dependency being briefly unavailable. And restart unless stopped isn't needed, because the reconciliation loop does that for you.

Finally, deploying changes from pushing over SSH, to Argo CD pulling the desired state from Git.

## 11. Further reading

The official documentation at kubernetes dot io is excellent, especially the Concepts section, and it pairs well with this introduction. You're allowed to use it during the CKAD exam, so getting comfortable with it now pays off later. The Gateway API, Argo CD and kind each have their own documentation sites as well.
