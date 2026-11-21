<div align="center">

## My Homelab repository

_... provisioned by OpenTofu and Ansible, reconciled by Argo CD_ :robot:

[![Proxmox](https://img.shields.io/badge/Proxmox-VE-E57000?style=for-the-badge&logo=proxmox&logoColor=white)](https://www.proxmox.com/)&nbsp;
[![OpenTofu](https://img.shields.io/badge/OpenTofu-IaC-FFDA18?style=for-the-badge&logo=opentofu&logoColor=black)](https://opentofu.org/)&nbsp;
[![Ansible](https://img.shields.io/badge/Ansible-config-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://www.ansible.com/)

Kubernetes cluster:

[![k3s](https://img.shields.io/badge/k3s-Kubernetes-FFC61C?style=for-the-badge&logo=k3s&logoColor=black)](https://k3s.io/)&nbsp;
[![Argo CD](https://img.shields.io/badge/Argo_CD-GitOps-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)&nbsp;
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com/)

</div>
<br>

👋 Hi. This is the umbrella repository for my Proxmox-based homelab and the k3s cluster running on it. It holds the OpenTofu layer and pulls in the Ansible playbooks and the Argo CD manifests as git submodules. I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [OpenTofu](https://opentofu.org/), [Ansible](https://www.ansible.com/), [k3s](https://k3s.io/), [Argo CD](https://argo-cd.readthedocs.io/) and [External Secrets](https://external-secrets.io/).

The repo is built in three layers, applied in order:

| Layer | What it does |
|-------|--------------|
| [01-opentofu](01-opentofu/proxmox/) | Builds an Ubuntu 24.04 cloud-init template on Proxmox, then clones VMs and creates LXCs from it |
| [02-ansible](02-ansible/) | Configures the hosts and bootstraps k3s with Argo CD |
| [03-argocd-kubernetes](03-argocd-kubernetes/) | App-of-apps that Argo CD syncs from `main`: MetalLB, Traefik, agentgateway, cert-manager, External Secrets, Dex, AdGuard Home, kube-prometheus-stack and more |

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full layout.

---

### :handshake: Thanks

A lot of inspiration for this repo comes from [bjw-s/home-ops](https://github.com/bjw-s-labs/home-ops), [Taegost/homelab-k8s](https://github.com/Taegost/homelab-k8s), the [Home Operations](https://discord.gg/home-operations) Discord community, and everyone sharing their clusters under the [k8s-at-home](https://github.com/topics/k8s-at-home) GitHub topic. Be sure to check out [Kubesearch](https://kubesearch.dev) for ideas on what to deploy and how.
