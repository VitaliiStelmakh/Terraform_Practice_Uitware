terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.94.0 "
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.6.0"}
  }  
  backend "azurerm" {
    resource_group_name   = "tfstate"
    storage_account_name  = "tfstateuvqbm"
    container_name        = "tfstate"
    key                   = "terraform.tfstate"
  }
}



provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}

# Resource Group
resource "azurerm_resource_group" "bestrong_rg" {
  name     = "bestrong_rg"
  location = "eastus"
}

# Virtual Network
resource "azurerm_virtual_network" "be_strong_vnet" {
  name                = "beStrongVNet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
}

# Subnet for App Service
resource "azurerm_subnet" "be_strong_app_subnet" {
  name                 = "beStrongAppSubnet"
  resource_group_name  = azurerm_resource_group.bestrong_rg.name
  virtual_network_name = azurerm_virtual_network.be_strong_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "delegation_app"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

}

# App Service Plan
resource "azurerm_service_plan" "be_strong_asp" {
  name                = "beStrongAppServicePlan"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  os_type             = "Linux"
  sku_name            = "B1"
}


# App Service
resource "azurerm_linux_web_app" "be_strong_as" {
  name                = "beStrongAppService"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  service_plan_id = azurerm_service_plan.be_strong_asp.id
  site_config {}


    app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app_insights.instrumentation_key
  }
   identity {
    type = "SystemAssigned"
  }

  storage_account {
    access_key   = azurerm_storage_account.be_strong_storage_account.primary_access_key
    account_name = azurerm_storage_account.be_strong_storage_account.name
    name         = "fileshare"
    share_name   = "fileshare"
    type         = "AzureFiles"
    mount_path   = "/file-share"
  }

}

resource "azurerm_app_service_virtual_network_swift_connection" "be_strong_vnet_swift_connection" {
  app_service_id      = azurerm_linux_web_app.be_strong_as.id
  subnet_id           = azurerm_subnet.be_strong_app_subnet.id
}



resource "azurerm_log_analytics_workspace" "be_strong_workspace" {
  name                = "beStrongWorkspace"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_application_insights" "app_insights" {
  name                = "beStrongAppInsights"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  workspace_id        = azurerm_log_analytics_workspace.be_strong_workspace.id
  application_type    = "web"
}


# Random String
resource "random_string" "acr_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Container Registry
resource "azurerm_container_registry" "be_strong_acr" {
  name                     = "beStrongAcr${random_string.acr_suffix.result}"
  resource_group_name      = azurerm_resource_group.bestrong_rg.name
  location                 = azurerm_resource_group.bestrong_rg.location
  sku                      = "Standard"
  admin_enabled            = false
}

# Role Assignment for App Service
resource "azurerm_role_assignment" "appservice_acr_pull" {
  scope                = azurerm_container_registry.be_strong_acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.be_strong_as.identity[0].principal_id
}


# Subnet for Key Vault

resource "azurerm_subnet" "be_strong_keyvault_subnet" {
  name                 = "beStrongKeyvaultSubnet"
  resource_group_name  = azurerm_resource_group.bestrong_rg.name
  virtual_network_name = azurerm_virtual_network.be_strong_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

service_endpoints = ["Microsoft.KeyVault"] # Adding Key Vault service endpoint

  delegation {
    name = "appServiceDelegation"
    
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  }

# Key Vault
resource "azurerm_key_vault" "be_strong_kv" {
  name                = "beStrongKV"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

   network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.be_strong_keyvault_subnet.id]
  }
}

# Access Policy for App Service
resource "azurerm_key_vault_access_policy" "app_service_access" {
  key_vault_id = azurerm_key_vault.be_strong_kv.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_linux_web_app.be_strong_as.identity[0].principal_id

  key_permissions = [
    "Get",
  ]

  secret_permissions = [
    "Get",
  ]

  certificate_permissions = [
    "Get",
  ]
}

# Subnet for SQL Server Endpoint
resource "azurerm_subnet" "be_strong_mssql_subnet" {
  name                 = "beStrongMssqlSubnet"
  resource_group_name  = azurerm_resource_group.bestrong_rg.name
  virtual_network_name = azurerm_virtual_network.be_strong_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
  }


resource "azurerm_mssql_server" "be_strong_sql_server" {
  name                         = "bestrongsqlserver123"
  resource_group_name          = azurerm_resource_group.bestrong_rg.name
  location                     = azurerm_resource_group.bestrong_rg.location
  version                      = "12.0"
  administrator_login          = var.sql_server_login
  administrator_login_password = var.sql_server_password
}

resource "azurerm_mssql_database" "be_strong_sql_db" {
  name           = "beStrongSqlDb"
  server_id      = azurerm_mssql_server.be_strong_sql_server.id
  sku_name       = "S0"
  max_size_gb    = 2
}


# Private Endpoint for SQL Server
resource "azurerm_private_endpoint" "be_strong_sql_private_endpoint" {
  name                = "beStrongSqlPrivateEndpoint"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  subnet_id           = azurerm_subnet.be_strong_mssql_subnet.id

  private_service_connection {
    name                           = "beStrongSqlPrivateServiceConnection"
    private_connection_resource_id = azurerm_mssql_server.be_strong_sql_server.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }
}
# Create a Storage Account
resource "azurerm_storage_account" "be_strong_storage_account" {
  name                     = "bestrongstorage123"
  resource_group_name      = azurerm_resource_group.bestrong_rg.name
  location                 = azurerm_resource_group.bestrong_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Subnet for Storage Account
resource "azurerm_subnet" "be_strong_storage_subnet" {
  name                 = "beStrongStorageSubnet"
  resource_group_name  = azurerm_resource_group.bestrong_rg.name
  virtual_network_name = azurerm_virtual_network.be_strong_vnet.name
  address_prefixes     = ["10.0.4.0/24"]
  }

# Endpoint for Storage Account
resource "azurerm_private_endpoint" "be_strong_storage_private_endpoint" {
  name                = "beStrongStoragePrivateEndpoint"
  location            = azurerm_resource_group.bestrong_rg.location
  resource_group_name = azurerm_resource_group.bestrong_rg.name
  subnet_id           = azurerm_subnet.be_strong_storage_subnet.id

  private_service_connection {
    name                           = "beStrongStoragePrivateServiceConnection"
    private_connection_resource_id = azurerm_storage_account.be_strong_storage_account.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }
}
















