data "google_client_config" "this" {}

# Read to find the DNS endpoint. The endpoint is not an output and no run prints it.
data "google_container_cluster" "this" {
  project  = var.project_id
  name     = "shiptrack"
  location = var.region
}

# The namespace, with the Pod Security restricted profile enforced (design 7.1). The AWS readiness-gate
# label is not used.
resource "kubernetes_namespace_v1" "shiptrack" {
  metadata {
    name = var.namespace

    labels = merge(local.labels, {
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
    })
  }
}

# What the deploy account may do, in this namespace and nowhere else (design 8.4). GKE gives it no
# cluster permission through IAM beyond fetching credentials, so everything it can do is below.
resource "kubernetes_role_v1" "deployer" {
  metadata {
    name      = "shiptrack-deployer"
    namespace = kubernetes_namespace_v1.shiptrack.metadata[0].name
    labels    = local.labels
  }

  # The workloads Helm installs.
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["services", "serviceaccounts", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["monitoring.googleapis.com"]
    resources  = ["podmonitorings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Helm keeps each release in a Secret. They hold no application secret (design 12).
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Reading what the rollout and the sampler show, and the port-forward of the contract run and the demo.
  rule {
    api_groups = [""]
    resources  = ["pods", "events", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/portforward"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "deployer" {
  metadata {
    name      = "shiptrack-deployer"
    namespace = kubernetes_namespace_v1.shiptrack.metadata[0].name
    labels    = local.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.deployer.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = local.deploy_user
  }
}
