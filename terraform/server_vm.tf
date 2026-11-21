resource "google_compute_instance" "server" {
  name         = "server-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["ssh", "grafana", "app-server"]

  labels = {
    project = "dice-devops-finalproject"
    role    = "server"
  }

  boot_disk {
    initialize_params {
      image = var.image
      size  = var.disk_size_gb
      type  = "pd-standard" # standard disk is covered by the free tier
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = var.server_internal_ip

    # Ephemeral public IP: needed for Grafana, SSH, Docker Hub and GitHub access.
    access_config {}
  }

  # Installs Docker + Compose and adds swap on first boot (safe to re-run on every boot).
  metadata_startup_script = file("${path.module}/scripts/startup.sh")

  metadata = {
    enable-oslogin = "TRUE"
  }

  service_account {
    scopes = ["logging-write", "monitoring-write"]
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # Allows `terraform apply` to change machine type without manual stop/start.
  allow_stopping_for_update = true
}
