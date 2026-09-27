terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Pinned to a minor series rather than floating, for the same reason as the network
      # module: a provider upgrade can change a default, and here a changed default on
      # immutable_tags or a cleanup policy deletes images nobody meant to delete.
      version = "~> 6.14"
    }
  }
}
