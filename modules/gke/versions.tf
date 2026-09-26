terraform {
  required_version = ">= 1.9"

  required_providers {
    # google-beta, not google, and only for this module.
    #
    # GKE Sandbox — gVisor — exists in gcloud and in the API, and `sandbox_config` appears
    # in no version of the `google` provider's schema. Without it there is no way to
    # express a gVisor node pool in Terraform, and gVisor is the isolation the whole
    # sandbox design rests on: HLD §10 assumes it, and Spike A's acceptance is that the
    # prototype's containment suite passes against it.
    #
    # The cost is that this module tracks a beta provider. The alternative was a node pool
    # created by gcloud outside Terraform, which is worse — it would be the one piece of
    # security-critical infrastructure nothing manages or plans.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.14"
    }
  }
}
