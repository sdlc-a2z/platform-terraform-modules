terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Pinned to a minor series rather than floating, same reasoning as every other
      # module here: a provider upgrade can change a default, and a changed default on
      # `ip_configuration` or `availability_type` is a silent loss of the isolation or the
      # HA this module exists to provide.
      version = "~> 6.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
