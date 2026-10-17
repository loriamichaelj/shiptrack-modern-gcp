output "topics" {
  description = "Topic names by flow: events and notifications."
  value       = { for flow, topic in google_pubsub_topic.this : flow => topic.name }
}

output "subscriptions" {
  description = "Subscription names by flow: events and notifications."
  value       = { for flow, subscription in google_pubsub_subscription.this : flow => subscription.name }
}

output "dead_letter_topics" {
  description = "Dead-letter topic names by flow."
  value       = { for flow, topic in google_pubsub_topic.dead_letter : flow => topic.name }
}

output "dead_letter_subscriptions" {
  description = "Subscriptions for inspecting dead letters, by flow."
  value       = { for flow, subscription in google_pubsub_subscription.dead_letter : flow => subscription.name }
}
