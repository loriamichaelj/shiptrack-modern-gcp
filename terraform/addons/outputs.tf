output "namespace" {
  description = "Name of the namespace the workloads run in."
  value       = kubernetes_namespace_v1.shiptrack.metadata[0].name
}
