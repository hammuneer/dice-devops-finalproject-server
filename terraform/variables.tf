variable "project_id" {
  description = "GCP project ID that will hold all resources"
  type        = string
}

# us-central1, us-west1 and us-east1 are the only regions where one e2-micro is free.
variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VM"
  type        = string
  default     = "us-central1-a"
}

variable "network_name" {
  description = "Name of the custom VPC network shared by the server and client VMs"
  type        = string
  default     = "devops-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet inside the VPC"
  type        = string
  default     = "devops-subnet"
}

variable "subnet_cidr" {
  description = "IP range of the subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "server_internal_ip" {
  description = "Fixed private IP of the server VM (the client connects to this address)"
  type        = string
  default     = "10.10.1.10"
}

variable "machine_type" {
  description = "VM size. e2-micro is covered by the GCP free tier"
  type        = string
  default     = "e2-micro"
}

variable "disk_size_gb" {
  description = "Boot disk size. Free tier includes 30 GB of standard persistent disk in total"
  type        = number
  default     = 10
}

variable "image" {
  description = "Boot image for the VM"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "app_port" {
  description = "TCP port the file server listens on"
  type        = number
  default     = 5000
}

variable "grafana_port" {
  description = "Port where Grafana is exposed on each VM"
  type        = number
  default     = 3020
}

variable "ssh_source_ranges" {
  description = "CIDR ranges allowed to SSH into the VMs. Narrow this to your own IP (x.x.x.x/32) if possible"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "grafana_source_ranges" {
  description = "CIDR ranges allowed to open Grafana"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
