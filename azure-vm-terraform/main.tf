# Create Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.azure_location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "nifi_cicd_project"
  }
}

# Create Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-nifi-dev"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-nifi-dev"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-nifi-dev"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow SSH
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow NiFi HTTPS
  security_rule {
    name                       = "AllowNiFiHTTPS"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow NiFi HTTP
  security_rule {
    name                       = "AllowNiFiHTTP"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow NiFi Registry
  security_rule {
    name                       = "AllowNiFiRegistry"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "18080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create Public IP
resource "azurerm_public_ip" "public_ip" {
  name                = "pip-nifi-dev"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Create Network Interface
resource "azurerm_network_interface" "nic" {
  name                = "nic-nifi-dev"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Associate NSG with Subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-nifi-dev"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = var.vm_size
  admin_username      = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    name                 = "osdisk-nifi-dev"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Install Docker, Docker Compose, Make, and Git
resource "azurerm_virtual_machine_extension" "docker_install" {
  name                 = "DockerInstall"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"

  settings = jsonencode({
    commandToExecute = <<-EOT
      bash -c '
      set -e
      
      # Update system
      echo "Updating system packages..."
      sudo apt-get update
      
      # Install Docker
      echo "Installing Docker..."
      curl -fsSL https://get.docker.com -o get-docker.sh
      sudo sh get-docker.sh
      rm get-docker.sh
      
      # Install Docker Compose
      echo "Installing Docker Compose..."
      sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      sudo chmod +x /usr/local/bin/docker-compose
      
      # Install Make and Git
      echo "Installing Make and Git..."
      sudo apt-get install -y make git
      
      # Add azureuser to docker group
      echo "Configuring Docker permissions..."
      sudo usermod -aG docker azureuser
      
      # Create project directory
      echo "Creating project directory..."
      sudo mkdir -p /opt/nifi_cicd_project
      sudo chown azureuser:azureuser /opt/nifi_cicd_project
      
      # Log completion
      echo "VM setup completed at $(date)" | sudo tee /var/log/vm-setup-complete.log
      echo "✅ Setup complete"
      '
    EOT
  })

  depends_on = [azurerm_linux_virtual_machine.vm]

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}