locals {
  labels = {
    environment = "dev"
    name        = "shiptrack"
  }

  # What each workload may use (design 7.3). The names come from the data root.
  topics        = data.terraform_remote_state.data.outputs.topics
  subscriptions = data.terraform_remote_state.data.outputs.subscriptions
  secrets       = data.terraform_remote_state.data.outputs.secret_ids
  signer        = "shiptrack-proof-of-delivery@${var.project_id}.iam.gserviceaccount.com"

  workloads = {
    api = {
      topics_publisher         = [local.topics["events"]]
      subscriptions_subscriber = []
      secrets_accessor         = [local.secrets["app"]]
      bucket_object_user       = true
      may_sign_as              = local.signer
    }
    worker-events = {
      topics_publisher         = [local.topics["notifications"]]
      subscriptions_subscriber = [local.subscriptions["events"]]
      secrets_accessor         = [local.secrets["app"]]
      bucket_object_user       = false
      may_sign_as              = null
    }
    worker-notify = {
      topics_publisher         = []
      subscriptions_subscriber = [local.subscriptions["notifications"]]
      secrets_accessor         = []
      bucket_object_user       = false
      may_sign_as              = null
    }
    sla-scan = {
      topics_publisher         = []
      subscriptions_subscriber = []
      secrets_accessor         = [local.secrets["app"]]
      bucket_object_user       = false
      may_sign_as              = null
    }
    migrate = {
      topics_publisher         = []
      subscriptions_subscriber = []
      secrets_accessor         = [local.secrets["migrator"]]
      bucket_object_user       = false
      may_sign_as              = null
    }
    db-init = {
      topics_publisher         = []
      subscriptions_subscriber = []
      secrets_accessor         = [local.secrets["admin"]]
      bucket_object_user       = false
      may_sign_as              = null
    }
  }
}
