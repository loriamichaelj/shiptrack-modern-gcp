module "network" {
  source = "../modules/network"

  project_id                     = var.project_id
  region                         = var.region
  subnet_cidr                    = var.subnet_cidr
  pods_cidr                      = var.pods_cidr
  services_cidr                  = var.services_cidr
  private_services_prefix_length = var.private_services_prefix_length
}

module "cloud_sql" {
  source = "../modules/cloud-sql"

  project_id                  = var.project_id
  region                      = var.region
  network_id                  = module.network.network_id
  private_services_connection = module.network.private_services_connection
  labels                      = local.labels
  deletion_protection         = var.deletion_protection
  admin_password              = ephemeral.random_password.db["admin"].result
  admin_password_version      = var.db_credentials_version
}

module "secrets" {
  source = "../modules/secrets"

  project_id          = var.project_id
  labels              = local.labels
  host                = module.cloud_sql.private_ip_address
  dbname              = module.cloud_sql.database_name
  admin_user          = module.cloud_sql.admin_user
  passwords           = { for account, password in ephemeral.random_password.db : account => password.result }
  credentials_version = var.db_credentials_version
}

module "pubsub" {
  source = "../modules/pubsub"

  project_id     = var.project_id
  project_number = var.project_number
  labels         = local.labels
}

module "proof_of_delivery_storage" {
  source = "../modules/proof-of-delivery-storage"

  project_id = var.project_id
  region     = var.region
  labels     = local.labels
  protection = var.proof_of_delivery_protection
}

module "ui_ingress" {
  source = "../modules/ui-ingress"

  project_id = var.project_id
}
