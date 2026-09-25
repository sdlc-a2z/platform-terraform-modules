terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Pinned to a minor series rather than floating: a provider upgrade can change a
      # default, and a changed default in a firewall module is a silent hole.
      version = "~> 6.14"
    }
  }
}
