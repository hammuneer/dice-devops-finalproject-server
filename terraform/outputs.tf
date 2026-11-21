output "network_name" {
  description = "VPC name (used by the client stack)"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "Subnet name (used by the client stack)"
  value       = google_compute_subnetwork.subnet.name
}

output "server_internal_ip" {
  description = "Private IP the client uses to reach the server"
  value       = google_compute_instance.server.network_interface[0].network_ip
}

output "server_external_ip" {
  description = "Public IP of the server VM"
  value       = google_compute_instance.server.network_interface[0].access_config[0].nat_ip
}

output "grafana_url" {
  description = "Grafana dashboard on the server VM"
  value       = "http://${google_compute_instance.server.network_interface[0].access_config[0].nat_ip}:${var.grafana_port}"
}

output "ssh_command" {
  description = "SSH into the server VM"
  value       = "gcloud compute ssh ${google_compute_instance.server.name} --zone ${var.zone} --project ${var.project_id}"
}
