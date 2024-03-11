
variable "subscription_id" {
    description = "The Azure Subscription ID"
  type = string
}

variable "tenant_id" {
    description = "The Azure Tenant ID"
  type = string
}

variable "client_id" {
    description = "The Azure Client ID"
  type = string
}

variable "client_secret" {
    description = "The Azure Client Secret"
  type = string
}

variable "sql_server_login" {
    description = "The login to SQL Server"
  type = string
}
variable "sql_server_password" {
    description = "The password to SQL Server"
  type = string
}