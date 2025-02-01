data "azuread_client_config" "current" {

}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}


resource "azurerm_key_vault" "kv" {
  name                = "kv-${var.project}-webapps"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tenant_id           = var.ARM_TENANT_ID
  sku_name            = "standard"

}


resource "azuread_application" "streamlit" {
  display_name = "streamlit-inapplogin-public"
  owners       = [data.azuread_client_config.current.object_id]

  // add api permissions to read the user, otherwise you will need to grant them yourself in the first login

  lifecycle {
    ignore_changes = [web] // this is for ignoring the redirect values
  }

}


resource "azuread_service_principal" "streamlit" {
  client_id                    = azuread_application.streamlit.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "time_rotating" "example" {
  rotation_days = 180
}

resource "azuread_service_principal_password" "streamlit" {
  service_principal_id = azuread_service_principal.streamlit.id
  rotate_when_changed = {
    rotation = time_rotating.example.id
  }
}

resource "azuread_application_password" "streamlit" {

  application_id = azuread_application.streamlit.id

}

resource "azurerm_key_vault_secret" "key" {
  name         = "${azuread_application.streamlit.display_name}-client-id"
  value        = azuread_application.streamlit.client_id
  key_vault_id = azurerm_key_vault.kv.id

}


resource "azurerm_key_vault_secret" "key-secret" {
  name         = "${azuread_application.streamlit.display_name}-client-secret"
  value        = azuread_application_password.streamlit.value
  key_vault_id = azurerm_key_vault.kv.id

}


// This resource block creates an Azure Linux Web App.

resource "azurerm_service_plan" "streamlit" {
  name                = "ASP-${var.project}-${terraform.workspace}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "B3"

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      tags
    ]
  }
}



resource "azurerm_linux_web_app" "app" {
  depends_on          = [azuread_application.streamlit, azurerm_service_plan.streamlit]
  name                = "webapp-st-${var.project}"
  location            = var.location
  service_plan_id     = azurerm_service_plan.streamlit.id
  resource_group_name = data.azurerm_resource_group.main.name
  https_only          = true


  identity {
    type = "SystemAssigned"
  }

  site_config {
    app_command_line = "python -m streamlit run app.py --server.port 8000 --server.address 0.0.0.0"

    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = true

    // Add other app settings as needed
  }
}


resource "azurerm_key_vault_access_policy" "streamlit_webapp" {
  key_vault_id = azurerm_key_vault.kv.id

  tenant_id = var.ARM_TENANT_ID
  object_id = azurerm_linux_web_app.app.identity.0.principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}


resource "azuread_application_redirect_uris" "app_redirect_uris" {
  depends_on     = [azuread_application.streamlit, azurerm_linux_web_app.app]
  application_id = azuread_application.streamlit.id
  type           = "Web"
  redirect_uris  = ["https://${azurerm_linux_web_app.app.name}.azurewebsites.net/oauth2callback", "http://localhost:8502/oauth2callback"]


}



resource "azurerm_key_vault_secret" "redirect_uri" {
  name         = "redirecturi"
  value        = "https://${azurerm_linux_web_app.app.name}.azurewebsites.net/oauth2callback"
  key_vault_id = azurerm_key_vault.kv.id

}

// this will create the secrets_toml file, the current app requires it, can't be in the os environment
resource "local_file" "secrets_toml" {
  content  = <<-EOT
  [auth]
  redirect_uri = "https://${azurerm_linux_web_app.app.name}.azurewebsites.net/oauth2callback"
  cookie_secret = "cookie"

  [auth.microsoft]
  redirect_uri = "https://${azurerm_linux_web_app.app.name}.azurewebsites.net/oauth2callback"
  client_id = "${azuread_application.streamlit.client_id}"
  client_secret = "${azuread_application_password.streamlit.value}"
  server_metadata_url = "https://login.microsoftonline.com/${var.ARM_TENANT_ID}/v2.0/.well-known/openid-configuration"
  client_kwargs = { 'prompt' = 'login' }
  EOT
  filename = "${path.module}/app/.streamlit/secrets.toml"
}



data "archive_file" "app" {
  depends_on = [ local_file.secrets_toml]
  type        = "zip"
  source_dir  = "./app"
  output_path = var.archive_file_streamlit

}

// This local block defines a command for publishing code to the Azure Web App (Linux).
locals {
  publish_code_command_linux = "az webapp deploy --resource-group ${azurerm_linux_web_app.app.resource_group_name} --name ${azurerm_linux_web_app.app.name} --src-path ${var.archive_file_streamlit}"
}

// This null_resource block publishes code to the Azure Web App (Linux) using the local-exec provisioner.
resource "null_resource" "app" {
  depends_on = [data.archive_file.app, local_file.secrets_toml]
  provisioner "local-exec" {
    command = local.publish_code_command_linux
  }
  
  triggers = {
    input_json           = filemd5(var.archive_file_streamlit)
    publish_code_command = local.publish_code_command_linux
  }
}
