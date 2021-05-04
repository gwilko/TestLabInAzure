terraform {
  required_providers {
    azurerm = "~>2.0"
  }
}

provider "azurerm" {
  features {}
}

variable "prefix" {
  default = "ansible"
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-resources"
  location = "australiasoutheast"
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_rule" "main" {
  name                        = "RDP and SSH access"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges      = ["22","3389"]
  source_address_prefix       = "14.2.117.75" #https://www.whatismyip.com/
  destination_address_prefixes  = ["10.0.2.5", "10.0.10.5"]
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_subnet" "internal" {
  name                 = "subnet_tools"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "main" {
  for_each             = var.subnets
  name                 = each.value["name"]
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value["ip"]]
}

resource "azurerm_public_ip" "main" {
  name                = "${var.prefix}-ubuntu--vm"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.prefix}-ubuntu--vm"
}

resource "azurerm_network_interface" "main" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Static"
    private_ip_address            = azurerm_network_security_rule.main.destination_address_prefix
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "azurerm_linux_virtual_machine" "main" {
  name                  = azurerm_public_ip.main.name
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  network_interface_ids = [azurerm_network_interface.main.id]
  size                  = "Standard_B2s"
  admin_username        = "ansibleadmin"
  admin_ssh_key {
    username   = "ansibleadmin"
    public_key = tls_private_key.main.public_key_openssh
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  tags = {
    environment = "ansible"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "main" {
  virtual_machine_id    = azurerm_linux_virtual_machine.main.id
  location              = azurerm_resource_group.main.location
  enabled               = true
  daily_recurrence_time = "1800"
  timezone              = "AUS Central Standard Time"
  notification_settings {
    enabled = false
  }
}

resource "azurerm_virtual_machine_extension" "main" {
  name                 = "${var.prefix}-ext"
  virtual_machine_id   = azurerm_linux_virtual_machine.main.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings             = <<SETTINGS
    {
        "fileUris":["https://raw.githubusercontent.com/globalbao/terraform-azurerm-ansible-linux-vm/master/scripts/ubuntu-setup-ansible.sh"]
    }
SETTINGS
  protected_settings   = <<PROTECTED_SETTINGS
    {
        "commandToExecute": ". ./ubuntu-setup-ansible.sh"
    }
PROTECTED_SETTINGS
}

resource "local_file" "private_key" {
  content  = tls_private_key.main.private_key_pem
  filename = "ansible-ubuntu-private.pem"
}

output "public_ip_address" {
  value = azurerm_public_ip.main.ip_address
}

output "public_key_pem" {
  value = tls_private_key.main.public_key_pem
}
