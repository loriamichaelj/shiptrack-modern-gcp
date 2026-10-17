# A budget of $50 a month (ADR-0028) that alerts and never stops anything. Credits count, so the GKE
# free-tier credit lowers the spend the budget sees. Alerts go to the email channel below and, because
# default recipients are not disabled, to the billing account's administrators and users.

resource "google_monitoring_notification_channel" "budget_email" {
  project      = var.project_id
  display_name = "ShipTrack budget alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "shiptrack"

  budget_filter {
    projects        = ["projects/${var.project_number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
  }
}
