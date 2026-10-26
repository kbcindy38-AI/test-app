terraform {
  required_version = ">= 1.5.0"

  backend "local" {
    path = "terraform.azure.tfstate"
  }
}

variable "subscription_id" {
  description = "Azure subscription where the application infrastructure will be created."
  type        = string
}

variable "acr_name" {
  description = "Globally unique Azure Container Registry name: 5-50 lowercase letters and numbers."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must contain 5-50 lowercase letters and numbers."
  }
}

variable "resource_group_name" {
  description = "Resource group for the application infrastructure."
  type        = string
  default     = "rg-hello-svc"
}

variable "location" {
  description = "Azure region for the application infrastructure."
  type        = string
  default     = "eastus"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy through OIDC, in owner/repository format."
  type        = string
  default     = "kbcindy38-AI/test-app"
}

variable "github_branch" {
  description = "GitHub branch allowed to deploy through OIDC."
  type        = string
  default     = "main"
}

resource "azurerm_resource_group" "app" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "app" {
  name                = "law-hello-svc"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_network" "app" {
  name                = "vnet-hello-svc"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_subnet" "container_apps" {
  name                 = "snet-container-apps"
  resource_group_name  = azurerm_resource_group.app.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = ["10.20.0.0/23"]

  delegation {
    name = "container-apps"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_container_registry" "app" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.app.name
  location            = azurerm_resource_group.app.location
  sku                 = "Basic"
  admin_enabled       = false
}

resource "azurerm_container_app_environment" "app" {
  name                       = "cae-hello-svc"
  location                   = azurerm_resource_group.app.location
  resource_group_name        = azurerm_resource_group.app.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.app.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
}

resource "azurerm_user_assigned_identity" "app_pull" {
  name                = "id-hello-svc-acr-pull"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app_pull.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_container_app" "app" {
  name                         = "ca-hello-svc"
  resource_group_name          = azurerm_resource_group.app.name
  container_app_environment_id = azurerm_container_app_environment.app.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_pull.id]
  }

  registry {
    server   = azurerm_container_registry.app.login_server
    identity = azurerm_user_assigned_identity.app_pull.id
  }

  template {
    container {
      name   = "hello-svc"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 80
    transport        = "auto"
  }

  lifecycle {
    ignore_changes = [
      template[0].container[0].image,
      ingress[0].target_port,
    ]
  }

  depends_on = [azurerm_role_assignment.app_acr_pull]
}

resource "azurerm_user_assigned_identity" "github_actions" {
  name                = "id-hello-svc-github"
  location            = azurerm_resource_group.app.location
  resource_group_name = azurerm_resource_group.app.name
}

resource "azurerm_federated_identity_credential" "github_actions" {
  name                = "github-main"
  resource_group_name = azurerm_resource_group.app.name
  parent_id           = azurerm_user_assigned_identity.github_actions.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"
}

resource "azurerm_role_assignment" "github_acr_build" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_container_app_deploy" {
  scope                = azurerm_container_app.app.id
  role_definition_name = "Container Apps Contributor"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
  principal_type       = "ServicePrincipal"
}

output "acr_name" {
  value = azurerm_container_registry.app.name
}

output "resource_group_name" {
  value = azurerm_resource_group.app.name
}

output "container_app_name" {
  value = azurerm_container_app.app.name
}

output "container_app_url" {
  value = "https://${azurerm_container_app.app.latest_revision_fqdn}"
}

output "github_client_id" {
  value = azurerm_user_assigned_identity.github_actions.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

data "azurerm_client_config" "current" {}
