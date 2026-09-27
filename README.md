# platform-terraform-modules

Reusable Terraform modules for the AI-Powered SDLC Platform. Composed by
[`platform-infra`](https://github.com/sdlc-a2z/platform-infra), which owns the
environments and the state.

## Why the split

A module and an environment change for different reasons and at different rates. An
environment changes when *this* deployment needs something; a module changes when the
shape of the thing changes everywhere. Keeping them together means every environment edit
touches the same history as every design change, and there is no version to pin.

Pinning is the point. `platform-infra` references a **tag**, so a change here reaches an
environment when someone bumps it — not the next time anyone runs `terraform apply`. For
modules that define a firewall, that difference is the whole safety story.

## Using a module

```hcl
module "network" {
  source = "git::https://github.com/sdlc-a2z/platform-terraform-modules.git//modules/network?ref=v0.2.0"

  project_id  = var.project_id
  region      = var.region
  environment = "dev"

  # No defaults for these. An address plan is a fact about a deployment, not about the
  # pattern, so it lives in the caller — which is private.
  subnets       = var.subnets
  pods_cidr     = var.pods_cidr
  services_cidr = var.services_cidr
}
```

## Public, and what that means

This repository is public so any caller can fetch it without a credential. That decision
followed three failed attempts at a narrow one — deploy keys are disabled across the
organisation and fine-grained tokens proved fiddly enough to cost six rounds — and the
organisation's posture reads as *no long-lived git credentials*, which public modules
agree with rather than route around.

**Nothing here describes a deployment.** The modules take every deployment-specific value
as an input: no address ranges, no project identifiers, no hostnames, no account numbers.
`terraform plan` against a real project happens in `platform-infra`, which is private and
holds the actual numbers.

What *is* visible is the shape: four network zones, which may reach which, and that a
sandbox is denied the metadata server. A firewall rule is not weaker for being readable —
it is weaker if it is wrong. Publishing the pattern and keeping the addresses is the split
that costs nothing and buys a credential nobody has to rotate.

**Do not add a default that names a real thing.** A CIDR, a project, a bucket, a hostname —
if it is true of one deployment, it belongs in that deployment's repository.

## Modules

| Module | | Story |
|---|---|---|
| [`network`](modules/network) | VPC, four zones, firewall, NAT | `R0-WS1-001` |
| [`gke`](modules/gke) | cluster, node pools, gVisor, Workload Identity | `R0-WS1-002` |
| [`artifact-registry`](modules/artifact-registry) | Docker registries, immutable tags, per-repository IAM | `R0-WS3-003` |
| `data` | Cloud SQL, Memorystore, Kafka, OpenSearch | `R0-WS1-004` |
| `observability` | OTel Collector, Prometheus, Grafana | `R0-WS1-005` |
| `temporal` | self-hosted cluster, own Postgres, Elasticsearch | `R0-WS1-007` |

Only `network`, `gke` and `artifact-registry` exist. The rest are named here so the shape is
visible before it is built, and so a story that invents a seventh module has to explain why.

## The rules

**A module takes inputs and returns outputs. It reads nothing.** No data sources against a
live project, no remote state lookups. A module that reads the world cannot be planned
without that world existing, which makes it untestable and makes `terraform plan` in CI
depend on whichever environment happens to be up.

**No `provider` blocks.** The caller configures providers. A provider inside a module
cannot be overridden and pins every consumer to one project and region.

**Every variable gets a description, and every dangerous default gets a comment saying
what it prevents.** The sandbox subnet's `private_ip_google_access` used to be the example
here — `false`, with a comment explaining that it looked like an oversight and was the
opposite.

It is now `true`, and the comment that defended it was wrong (ADR-0009). It reasoned about
what a *pod* could reach and set a flag that governs the *node*, which is the exact
confusion ADR-0008 was written to correct. Off, the node could pull no image from anywhere
and the firewall's `sandbox-allow-google-apis` rule permitted a destination with no route
to it — a control that looked like it was doing something.

The rule survives the example. A comment saying what a default prevents is worth having;
it is also the thing nobody re-reads, so it outlives the reasoning behind it. **Prefer a
check to a comment** where one is possible.

**Tag every change.** `terraform fmt`, `terraform validate`, then a tag. Consumers pin, so
an untagged change reaches nobody — which is correct, and also means forgetting to tag
looks exactly like doing nothing.

## Checks

```bash
make check      # fmt and validate every module — no credentials, no cloud project
```

Validation needs no credentials because of the first rule above. That is not a coincidence:
a module that could not be validated offline would be one that reads the world.

## The `gke` module uses `google-beta`

Deliberately, and only this module. GKE Sandbox — gVisor — appears in `gcloud` and in the
API, and `sandbox_config` exists in no version of the `google` provider's schema. Without
it a gVisor node pool cannot be expressed in Terraform at all.

That matters because gVisor is not a nicety here: HLD §10 rests the sandbox design on it,
and Spike A's acceptance is that the prototype's containment suite passes against it. The
alternative was a node pool created by `gcloud` outside Terraform — the one piece of
security-critical infrastructure that nothing manages, plans or drifts against.

If `sandbox_config` ever lands in the `google` provider, switching back is one line.
