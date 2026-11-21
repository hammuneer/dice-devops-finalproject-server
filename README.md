# dice-devops-finalproject-server

[![CI/CD - server](https://github.com/hammuneer/dice-devops-finalproject-server/actions/workflows/ci-cd.yml/badge.svg)](https://github.com/hammuneer/dice-devops-finalproject-server/actions/workflows/ci-cd.yml)

Server half of a DevOps capstone project. A Python server, packaged as a Docker image, creates a
1 KB file of random text and sends it together with its SHA-256 checksum to a client. The project
covers the whole workflow around it: containers, infrastructure as code on **Google Cloud (GCP)**,
monitoring with Grafana, and a CI/CD pipeline that deploys to the VM through a self-hosted GitHub runner.

| Component | Repository |
|---|---|
| Server (this repo) | https://github.com/hammuneer/dice-devops-finalproject-server |
| Client | https://github.com/hammuneer/dice-devops-finalproject-client |
| Docker images | [hammuneer/dice-devops-finalproject-server](https://hub.docker.com/r/hammuneer/dice-devops-finalproject-server), [hammuneer/dice-devops-finalproject-client](https://hub.docker.com/r/hammuneer/dice-devops-finalproject-client) |

> The original brief targets AWS EC2. This implementation uses the GCP equivalents:
> EC2 → Compute Engine, t2.micro → e2-micro (free tier), VPC/subnets → custom-mode VPC + subnet,
> security groups → VPC firewall rules.

---

## Table of contents

1. [Architecture](#1-architecture)
2. [Repository layout](#2-repository-layout)
3. [How the application works](#3-how-the-application-works)
4. [Prerequisites](#4-prerequisites)
5. [Run locally with Docker Compose](#5-run-locally-with-docker-compose)
6. [Create the infrastructure with Terraform (GCP)](#6-create-the-infrastructure-with-terraform-gcp)
7. [Monitoring stack (Grafana on port 3020)](#7-monitoring-stack-grafana-on-port-3020)
8. [CI/CD pipeline](#8-cicd-pipeline)
9. [Day-to-day usage](#9-day-to-day-usage)
10. [Cost control](#10-cost-control)
11. [Troubleshooting](#11-troubleshooting)
12. [Tear down](#12-tear-down)

---

## 1. Architecture

```
                 GitHub: dice-devops-finalproject-server / -client
                        │ git push (main)
                        ▼
        ┌──────── GitHub Actions ────────┐
        │ build + test  (GitHub-hosted)  │──push──▶ Docker Hub (public images)
        │ deploy        (self-hosted)    │                │ pull
        │ notify        (GitHub-hosted)  │──▶ Slack       │
        └───────────────┬────────────────┘                │
                        │                                 │
  GCP project ── VPC "devops-vpc" ── subnet 10.10.1.0/24 (us-central1)
  ┌─────────────────────────────────────┐   ┌─────────────────────────────────────┐
  │ server-vm  10.10.1.10   e2-micro    │   │ client-vm  10.10.1.20   e2-micro    │
  │  • GitHub runner (label server-vm)  │   │  • GitHub runner (label client-vm)  │
  │  • file-server  :5000  ◀────────────┼───┼── file-client (every 60 s)          │
  │    volume servervol → /serverdata   │TCP│    volume clientvol → /clientdata   │
  │  • Grafana :3020, Prometheus,       │   │  • Grafana :3020, Prometheus,       │
  │    node-exporter, cAdvisor          │   │    node-exporter, cAdvisor          │
  └─────────────────────────────────────┘   └─────────────────────────────────────┘
  Firewall: internal traffic within 10.10.1.0/24 · SSH 22 · Grafana 3020 from the internet
            (port 5000 is NOT reachable from the internet, only from inside the VPC)
```

## 2. Repository layout

```
.
├── app/
│   ├── server.py              # TCP file server
│   └── healthcheck.py         # Docker HEALTHCHECK (checks the port is listening)
├── Dockerfile                 # python:3.12-slim, non-root user, VOLUME /serverdata
├── docker-compose.yml         # service "server", named volume "servervol"
├── monitoring/                # Prometheus + Grafana + node-exporter + cAdvisor
│   ├── docker-compose.yml
│   ├── prometheus/prometheus.yml
│   └── grafana/{provisioning,dashboards}/
├── terraform/                 # VPC, subnet, firewall rules, server VM
│   ├── versions.tf  variables.tf  network.tf  server_vm.tf  outputs.tf
│   ├── terraform.tfvars.example
│   └── scripts/startup.sh     # VM bootstrap: swap + Docker + Compose
├── scripts/setup-runner.sh    # registers the VM as a self-hosted GitHub runner
└── .github/workflows/ci-cd.yml
```

## 3. How the application works

For every TCP connection on port **5000** the server:

1. writes a new 1024-byte file of random letters/digits to `/serverdata` (e.g. `data_20261121T205255Z.txt`);
2. computes its SHA-256 checksum;
3. sends a one-line JSON header followed by the raw file bytes:

```
{"filename": "data_20261121T205255871877Z.txt", "size": 1024, "checksum": "c03c79...d4c"}\n
<1024 bytes of file content>
```

Only the newest 50 files are kept so the volume does not grow forever. The client reads the header,
saves the file to `/clientdata`, re-hashes it and logs `Checksum VERIFIED` or `Checksum MISMATCH`.

Configuration (environment variables):

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_PORT` | `5000` | Listening port |
| `DATA_DIR` | `/serverdata` | Where files are written |
| `FILE_SIZE_BYTES` | `1024` | Size of each generated file |
| `MAX_FILES` | `50` | Files kept in the volume |

The image uses the official `python:3.12-slim` base, installs `tini` (a minimal init that forwards
`docker stop` signals correctly), runs as a non-root user and declares a health check.

## 4. Prerequisites

| Tool / account | Used for | Check |
|---|---|---|
| Docker Desktop / Engine with Compose v2 | Local build & run | `docker compose version` |
| Git + GitHub account, GitHub CLI `gh` | Repos, secrets, runner tokens | `gh auth status` |
| Google Cloud account with billing enabled | VMs | — |
| Google Cloud SDK `gcloud` | Auth, SSH | `gcloud --version` |
| Terraform ≥ 1.6 | Infrastructure as code | `terraform version` |
| Docker Hub account + access token (Read & Write) | Image registry | — |
| Slack workspace + incoming webhook | Deployment notifications | — |

Install on macOS: `brew install --cask docker google-cloud-sdk && brew install gh hashicorp/tap/terraform`.

## 5. Run locally with Docker Compose

```bash
git clone https://github.com/hammuneer/dice-devops-finalproject-server.git
cd dice-devops-finalproject-server
docker compose up -d --build
docker compose logs -f              # "Listening on 0.0.0.0:5000 ..."
```

Test it with the client (in the client repo):

```bash
git clone https://github.com/hammuneer/dice-devops-finalproject-client.git
cd dice-devops-finalproject-client
FETCH_INTERVAL_SECONDS=5 docker compose up -d --build
docker logs -f file-client         # "... Checksum VERIFIED: <sha256>"
```

> **macOS note:** port 5000 is taken by AirPlay Receiver. Use another host port:
> `SERVER_PORT=5050 docker compose up -d` (server) and `SERVER_PORT=5050 docker compose up -d` (client).

Inspect the volume: `docker run --rm -v servervol:/d alpine ls -l /d`

Stop: `docker compose down` (add `-v` to delete the volume).

## 6. Create the infrastructure with Terraform (GCP)

The **server repo owns the shared network** (VPC, subnet, firewall rules) plus the server VM.
The client repo only creates the client VM inside that network, so **apply this repo first**.

### 6.1 One-time GCP setup

```bash
gcloud auth login
gcloud auth application-default login          # credentials Terraform uses

PROJECT_ID=dice-devops-finalproject            # must be globally unique
gcloud projects create $PROJECT_ID
gcloud billing accounts list                   # pick your billing account ID
gcloud billing projects link $PROJECT_ID --billing-account=XXXXXX-XXXXXX-XXXXXX
gcloud config set project $PROJECT_ID
gcloud services enable compute.googleapis.com

# Optional but recommended: e-mail alerts at 20/50/90/100 % of a $5 budget
gcloud services enable billingbudgets.googleapis.com
gcloud billing budgets create --billing-account=XXXXXX-XXXXXX-XXXXXX \
  --display-name="$PROJECT_ID-5usd" --budget-amount=5USD \
  --filter-projects=projects/$PROJECT_ID \
  --threshold-rule=percent=0.2 --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
```

### 6.2 Apply

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set project_id
terraform init
terraform plan                                 # 6 resources to add
terraform apply
terraform output
```

What gets created:

| Resource | Details |
|---|---|
| `google_compute_network.vpc` | `devops-vpc`, custom mode (no auto subnets) |
| `google_compute_subnetwork.subnet` | `devops-subnet`, `10.10.1.0/24`, us-central1 |
| `google_compute_firewall.allow_internal` | all TCP/UDP/ICMP **within the subnet** (server ↔ client, port 5000) |
| `google_compute_firewall.allow_ssh` | TCP 22 → VMs tagged `ssh` |
| `google_compute_firewall.allow_grafana` | TCP 3020 → VMs tagged `grafana` |
| `google_compute_instance.server` | `server-vm`, e2-micro, Debian 12, 10 GB pd-standard, fixed IP `10.10.1.10`, ephemeral public IP |

On first boot `terraform/scripts/startup.sh` adds 2 GB swap, installs Docker Engine + Compose plugin
from Docker's official repository and limits container log size. Progress:
`gcloud compute ssh server-vm --zone us-central1-a --command 'sudo tail -f /var/log/vm-bootstrap.log'`

Key variables (`variables.tf`): `region` / `zone` (default `us-central1` / `us-central1-a`, a free-tier region),
`machine_type` (`e2-micro`), `subnet_cidr`, `server_internal_ip`, `ssh_source_ranges`
(narrow to `["<your-ip>/32"]` for better security), `grafana_source_ranges`.

> **State:** `terraform.tfstate` is kept locally and is git-ignored. Do not delete it, or Terraform
> loses track of the resources. For team use, move it to a GCS backend.

## 7. Monitoring stack (Grafana on port 3020)

`monitoring/docker-compose.yml` runs four containers on each VM:

| Container | Purpose |
|---|---|
| `node-exporter` | Host metrics: CPU, memory, swap, disk, network, load |
| `cadvisor` | Per-container metrics: CPU, memory, network |
| `prometheus` | Scrapes both every 15–30 s, keeps 3 days / 500 MB |
| `grafana` | Dashboards, published on **host port 3020** (only this port is exposed) |

Grafana is provisioned from files, so nothing is configured by hand:
the Prometheus data source and two dashboards in the **DevOps Capstone** folder:

- **Host System Metrics** (home dashboard): CPU / memory / swap / disk gauges, uptime, load,
  CPU by mode, memory, disk space, network traffic, disk I/O.
- **Docker Container Metrics**: running containers, CPU, memory and network per container,
  and a table with image, memory, CPU and uptime of every container.

Access: `http://<server-vm public IP>:3020` (`terraform output grafana_url`).
Dashboards are viewable anonymously (read-only). Admin login is `admin` with a random password
generated on the VM:

```bash
gcloud compute ssh server-vm --zone us-central1-a --command 'sudo cat /opt/monitoring/.env'
```

The pipeline (section 8) copies `monitoring/` to `/opt/monitoring` and runs
`docker compose up -d` on every deploy, so changes to dashboards or Prometheus config are deployed
automatically. Memory limits are set for each container to fit an e2-micro (total ≈ 170 MB in use).

## 8. CI/CD pipeline

`.github/workflows/ci-cd.yml` runs on every push to `main` (except changes to `*.md` and
`terraform/**`) and on manual dispatch.

| Job | Runs on | Steps |
|---|---|---|
| **build** | `ubuntu-latest` (GitHub-hosted) | Python syntax check → build image → **smoke test** (start the container, fetch a file, verify size and checksum) → log in to Docker Hub → push `:<short-sha>` and `:latest` |
| **deploy** | `[self-hosted, server-vm]` | Checkout → copy `docker-compose.yml` to `/opt/dice-server` and **rewrite the image tag to `<short-sha>`** → `docker compose pull` → `docker compose up -d` → wait until the container is `healthy` → **automatic rollback** to the previous compose file on failure → sync monitoring stack → `docker image prune -af` |
| **notify** | `ubuntu-latest` | Posts ✅/❌ to Slack with repo, image tag, target VM, job results, commit message, author and a link to the run |

### 8.1 Secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub personal access token (Read & Write) for user `hammuneer` |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL (`https://hooks.slack.com/services/...`) |

Set them from the CLI without the value ever appearing on screen (copy the value first):

```bash
gh secret set DOCKERHUB_TOKEN   --body "$(pbpaste)" -R hammuneer/dice-devops-finalproject-server
gh secret set SLACK_WEBHOOK_URL --body "$(pbpaste)" -R hammuneer/dice-devops-finalproject-server
```

If `SLACK_WEBHOOK_URL` is missing the notify job skips sending instead of failing.

**Slack webhook:** api.slack.com/apps → *Create New App* → *From scratch* → *Pick features* →
tick *Incoming Webhooks* (bot scope `incoming-webhook`) → *Install to Workspace* → choose the
channel → *Allow* → *Incoming Webhooks* page → copy the URL.

### 8.2 Register the VM as a private runner

```bash
TOKEN=$(gh api -X POST repos/hammuneer/dice-devops-finalproject-server/actions/runners/registration-token -q .token)
gcloud compute scp scripts/setup-runner.sh server-vm:/tmp/ --zone us-central1-a
gcloud compute ssh server-vm --zone us-central1-a --command \
  "sudo bash /tmp/setup-runner.sh hammuneer/dice-devops-finalproject-server $TOKEN server-vm /opt/dice-server"
```

The script creates a `runner` user (member of the `docker` group, no sudo), creates `/opt/dice-server`
and `/opt/monitoring` (with a generated Grafana password in `/opt/monitoring/.env`), downloads the
latest GitHub Actions runner, registers it with the label **`server-vm`** and installs it as a systemd
service so it survives reboots. Check: repo → Settings → Actions → Runners → `server-vm` *Idle*.

**Security for a public repo with a self-hosted runner:** require approval before workflows from
outside contributors run, so nobody can execute code on the VM through a pull request:

```bash
gh api -X PUT repos/hammuneer/dice-devops-finalproject-server/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
```

### 8.3 First deployment

Push any commit to `main` (or *Actions → CI/CD - server → Run workflow*). After about 3 minutes:

```bash
gcloud compute ssh server-vm --zone us-central1-a --command 'docker ps; grep image: /opt/dice-server/docker-compose.yml'
# file-server   hammuneer/dice-devops-finalproject-server:6bcfa77   Up (healthy)
```

## 9. Day-to-day usage

| Task | Command |
|---|---|
| Deploy a change | `git commit -am "..." && git push` |
| Redeploy without changes | `gh workflow run ci-cd.yml` |
| Watch the pipeline | `gh run watch` |
| Server logs | `gcloud compute ssh server-vm --zone us-central1-a --command 'docker logs --tail 20 file-server'` |
| Files in the volume | `... --command 'docker run --rm -v servervol:/d alpine ls -l /d'` |
| Deployed version | `... --command 'grep image: /opt/dice-server/docker-compose.yml'` |
| Roll back manually | edit the tag in `/opt/dice-server/docker-compose.yml`, then `docker compose up -d` |
| Current IPs / URLs | `cd terraform && terraform refresh && terraform output` |

## 10. Cost control

Target: **under $5** for the whole assignment.

- One e2-micro per billing account is free in us-central1/us-west1/us-east1; the second VM costs ≈ $0.20/day.
- Two 10 GB `pd-standard` disks fit inside the 30 GB free tier.
- Ephemeral public IPs cost ≈ $0.12/day each while the VM runs.
- Image builds run on free GitHub-hosted runners, not on the VMs.
- A $5 budget alert e-mails at 20/50/90/100 %.
- **Stop the VMs when not in use** (stopped VMs cost nothing apart from the free disks):

```bash
gcloud compute instances stop  server-vm client-vm --zone us-central1-a
gcloud compute instances start server-vm client-vm --zone us-central1-a
```

After a start the **public IPs change** (private IPs stay the same); get the new Grafana URL with
`terraform refresh && terraform output grafana_url`. Containers and runners start automatically.

## 11. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `bind: address already in use` for port 5000 on macOS | AirPlay Receiver uses 5000. Run with `SERVER_PORT=5050`. |
| Terraform: `could not find default credentials` | Run `gcloud auth application-default login` (tick all permissions on the consent screen). |
| Terraform: `Compute Engine API has not been used` | `gcloud services enable compute.googleapis.com` |
| `docker: command not found` right after `apply` | Bootstrap still running, wait 2–3 min: `sudo tail /var/log/vm-bootstrap.log` |
| Deploy job stays *Queued* | Runner offline. Check `sudo systemctl status 'actions.runner.*'` on the VM, or Settings → Actions → Runners. Start the VM if it is stopped. |
| Build job: `unauthorized: incorrect username or password` | `DOCKERHUB_TOKEN` is wrong or expired. Create a new token and set the secret again. |
| Deploy job: `permission denied ... docker.sock` | `runner` user not in `docker` group: `sudo usermod -aG docker runner && sudo systemctl restart 'actions.runner.*'` |
| Container `unhealthy`, pipeline rolled back | `docker logs file-server`; the previous version keeps running. |
| Grafana not reachable on :3020 | `docker ps` → is `grafana` running? `docker logs grafana`. Check the firewall rule `devops-vpc-allow-grafana` and that you use the **current** public IP. |
| Grafana restarts with `yaml: control characters are not allowed` | Hidden `._*` files copied from macOS. Copy files with `git archive` or set `COPYFILE_DISABLE=1`. |
| Dashboard panels show *No data* | `docker exec prometheus wget -qO- localhost:9090/api/v1/targets` → all targets should be `up`. |
| VM slow / OOM | `free -m`; the 2 GB swap should be active (`swapon --show`). Consider `machine_type = "e2-small"`. |
| Disk full | `docker system df`; `docker image prune -af`. The pipeline prunes after every deploy. |
| No Slack message | Check the `SLACK_WEBHOOK_URL` secret; test: `curl -X POST -H 'Content-Type: application/json' -d '{"text":"test"}' <url>` |

## 12. Tear down

Destroy the client stack **first** (it uses this repo's network), then this one:

```bash
cd ../dice-devops-finalproject-client/terraform && terraform destroy
cd ../../dice-devops-finalproject-server/terraform && terraform destroy
```

Optionally remove the runners (Settings → Actions → Runners → Remove) and delete the project:
`gcloud projects delete dice-devops-finalproject`.
