
We've set up our [first service on our k3s cluster](001-setup-homepage.mdx) and managed to access it from the outside (our localhost). We managed to do this, in part, because of Kubernetes' built-in Ingress API (networking.k8s.io/v1). 

# Installing Traefik into our k3s cluster via Helm
```bash
helm upgrade --install traefik traefik/traefik \
  --version 41.6.0 \
  --namespace traefik --create-namespace 
```

Wait for about 10 seconds for Traefik to fully start up and check that it is running with an external IP address
```bash
kubectl get po,svc -A 
```

```
NAMESPACE     NAME                                          READY   STATUS    RESTARTS   AGE
kube-system   pod/coredns-54bf7cdff9-sds4b                  1/1     Running   0          7m35s
kube-system   pod/local-path-provisioner-69879d7dd7-g7c2z   1/1     Running   0          7m35s
kube-system   pod/metrics-server-77dbbf84b-fr62f            1/1     Running   0          7m35s
kube-system   pod/svclb-traefik-0571c0af-78dv7              2/2     Running   0          89s
traefik       pod/traefik-6979fc9c79-t6x8p                  1/1     Running   0          89s

NAMESPACE     NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
default       service/kubernetes       ClusterIP      10.43.0.1      <none>        443/TCP                      7m41s
kube-system   service/kube-dns         ClusterIP      10.43.0.10     <none>        53/UDP,53/TCP,9153/TCP       7m39s
kube-system   service/metrics-server   ClusterIP      10.43.108.15   <none>        443/TCP                      7m39s
traefik       service/traefik          LoadBalancer   10.43.158.49   192.168.5.1   80:30681/TCP,443:30257/TCP   89s
```

In my case, Traefik has an external IP address of 192.168.5.1


## Ingress vs. IngressRoute

Kubernetes has a built-in `Ingress` resource, and Traefik has its own `IngressRoute` CRD. Both route outside traffic to Services inside the cluster, so why are there two?

### Ingress is only a spec

`networking.k8s.io/v1 Ingress` is a standard Kubernetes object, but on its own it does nothing. It describes the routing we want ("send `homepage.my.network` to Service `homepage:3000`"), but an **ingress controller** has to read it and do the routing. Traefik, ingress-nginx and HAProxy are all ingress controllers. Each one watches Ingress objects across the cluster and turns them into its own routing config.

Our Homepage `ingress.yaml` doesn't set an `ingressClassName`, so it relies on the cluster having a *default* IngressClass. The Traefik Helm chart we just installed registers a `traefik` IngressClass and marks it as the default. Check with:

```bash
kubectl get ingressclass
```

### Ingress is portable but limited

The Ingress spec only covers what every controller can agree on:

- matching on host and path
- routing to a Service and port
- TLS using a certificate stored in a Secret

Anything beyond that, like redirects, auth, header rewrites, rate limits or TCP routing, requires **controller-specific annotations**. These are plain strings that only one controller understands. For example, to attach a Traefik middleware to an Ingress:

```yaml
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-redirect-https@kubernetescrd
```

To 

Annotations work, but they are a hacky workaround. For one thing, there's no way to validate your annotations--a typo in either the key or value is silently ignored.

### IngressRoute is Traefik's own resource

Traefik added its own CRD (`traefik.io/v1alpha1 IngressRoute`) so its features have actual typed fields instead of annotations. Here's the same Homepage route written as an IngressRoute:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: homepage
  namespace: default
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`homepage.my.network`)
      kind: Rule
      middlewares:
        - name: redirect-https
      services:
        - name: homepage
          port: 3000
```

Compared with an Ingress, we get:

- **Rule expressions**: `Host(...) && PathPrefix(...)`, plus matching on headers, query parameters or client IP.
- **Middlewares as references**: separate typed `Middleware` objects for auth, redirects, headers and so on, instead of annotation strings.
- **Entry points**: we choose which Traefik listener(s) the route is attached to.
- **More protocols**: `IngressRouteTCP` and `IngressRouteUDP` for non-HTTP traffic. Plain Ingress can't do this.
- **Weighted and mirrored services**, useful for canary deploys.

The cost is that it only works with Traefik.

| | Ingress | IngressRoute |
|---|---|---|
| Defined by | Kubernetes (built-in) | Traefik (CRD) |
| Works with | Any ingress controller | Traefik only |
| Advanced features | Through annotation strings | Typed fields |
| TCP/UDP | No | Yes |

### Gateway API is the future

Kubernetes' own answer to Ingress's limits is the **Gateway API** (`Gateway`, `HTTPRoute`, ...). It's built in, expressive like IngressRoute, and portable across controllers, and Traefik supports it. That's why Homepage's ClusterRole also grants read access to `httproutes` and `gateways`, alongside `ingresses` and `ingressroutes`. Homepage can discover services from all three.

### Which one should we use?

For now, we'll keep the plain Ingress. It's simple, works with any controller, and is what Homepage's docs use. We'll move to IngressRoute when we need a Traefik feature, such as HTTPS redirects, basic auth, or non-HTTP services. Gateway API is worth a look if we ever redesign the routing setup from scratch.
