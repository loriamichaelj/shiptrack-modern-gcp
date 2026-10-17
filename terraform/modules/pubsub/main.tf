# Queues and notifications (ADR-0009). Two flows, each a topic with one pull subscription that
# dead-letters to a second topic after five attempts, and a pull subscription on that second topic so
# a person can inspect what failed:
#
#   events         the api publishes, worker-events pulls. Retention 4 days.
#   notifications  worker-events publishes ShipmentDelivered and ShipmentException, worker-notify pulls
#                  through a filter on the detail_type attribute. Topic retention 7 days, which keeps
#                  replay (seek) that the AWS archive gave.
#
# The workloads' own access to these resources is granted with the cluster (ADR-0029).

locals {
  flows = {
    events = {
      topic                  = "shiptrack-carrier-events"
      subscription           = "shiptrack-carrier-events-worker"
      topic_retention        = null
      subscription_retention = "345600s"
      filter                 = null
    }
    notifications = {
      topic                  = "shiptrack-notifications"
      subscription           = "shiptrack-notifications-worker"
      topic_retention        = "604800s"
      subscription_retention = "604800s"
      filter                 = "attributes.detail_type = \"ShipmentDelivered\" OR attributes.detail_type = \"ShipmentException\""
    }
  }

  pubsub_service_agent = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_topic" "this" {
  #checkov:skip=CKV_GCP_83: Google-managed encryption is enough for a dev queue, and a customer-managed key costs a key plus operations.
  for_each = local.flows

  project                    = var.project_id
  name                       = each.value.topic
  labels                     = var.labels
  message_retention_duration = each.value.topic_retention
}

resource "google_pubsub_topic" "dead_letter" {
  #checkov:skip=CKV_GCP_83: Google-managed encryption is enough for a dev queue, and a customer-managed key costs a key plus operations.
  for_each = local.flows

  project = var.project_id
  name    = "${each.value.topic}-dead-letter"
  labels  = var.labels
}

# Never expire: a subscription with no activity for 31 days is deleted by default.
resource "google_pubsub_subscription" "this" {
  for_each = local.flows

  project                    = var.project_id
  name                       = each.value.subscription
  topic                      = google_pubsub_topic.this[each.key].id
  labels                     = var.labels
  ack_deadline_seconds       = 60
  message_retention_duration = each.value.subscription_retention
  filter                     = each.value.filter

  expiration_policy {
    ttl = ""
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter[each.key].id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_subscription" "dead_letter" {
  for_each = local.flows

  project                    = var.project_id
  name                       = "${each.value.topic}-dead-letter-inspect"
  topic                      = google_pubsub_topic.dead_letter[each.key].id
  labels                     = var.labels
  message_retention_duration = "1209600s"

  expiration_policy {
    ttl = ""
  }
}

# Dead-lettering is done by Pub/Sub's service agent: it publishes to the dead-letter topic and
# acknowledges on the source subscription.
resource "google_pubsub_topic_iam_member" "dead_letter_publisher" {
  for_each = local.flows

  project = var.project_id
  topic   = google_pubsub_topic.dead_letter[each.key].name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_service_agent
}

resource "google_pubsub_subscription_iam_member" "source_subscriber" {
  for_each = local.flows

  project      = var.project_id
  subscription = google_pubsub_subscription.this[each.key].name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_service_agent
}
