# ---------------------------------------------------------------------------
# Shared network for both VMs. The client repo looks these up by name, so
# this stack must be applied first.
# ---------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false # custom mode: we define our own subnet
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  name                     = var.subnet_name
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# Firewall rules (GCP's equivalent of AWS security groups).
# Rules target VMs by network tag, so the client VM only needs the same tags.
# ---------------------------------------------------------------------------

# Server <-> client traffic over private IPs (includes the app port 5000).
resource "google_compute_firewall" "allow_internal" {
  name          = "${var.network_name}-allow-internal"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = [var.subnet_cidr]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name          = "${var.network_name}-allow-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = var.ssh_source_ranges
  target_tags   = ["ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_grafana" {
  name          = "${var.network_name}-allow-grafana"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = var.grafana_source_ranges
  target_tags   = ["grafana"]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.grafana_port)]
  }
}
