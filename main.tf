data "vsphere_datacenter" "dc" {
  name = var.dc
}

data "vsphere_datastore_cluster" "datastore_cluster" {
  count         = var.datastore_cluster != "" ? 1 : 0
  name          = var.datastore_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  count         = var.datastore != "" && var.datastore_cluster == "" ? 1 : 0
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "disk_datastore" {
  count         = var.disk_datastore != "" ? 1 : 0
  name          = var.disk_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.vmrp
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_distributed_virtual_switch" "vds" {
  count         = (var.dc == "PAU-Prod" || var.dc == "ANGERS-Prod") ? 1 : 0
  name          = format("%s%s", "DSwitch-LAN-", var.dc)
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  count = length(var.network)
  name  = keys(var.network)[count.index]
  #distributed_virtual_switch_uuid = (var.dc == "PAU-Prod" || var.dc == "ANGERS-Prod") && var.datastore == null ? data.vsphere_distributed_virtual_switch.vds[0].id : null
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  count         = var.content_library == null ? 1 : 0
  name          = var.vmtemp
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_content_library" "library" {
  count      = var.content_library != null ? 1 : 0
  name       = var.content_library
  depends_on = [var.tag_depends_on]
}

data "vsphere_content_library_item" "library_item_template" {
  count      = var.content_library != null ? 1 : 0
  library_id = data.vsphere_content_library.library[0].id
  type       = "ovf"
  name       = var.vmtemp
  depends_on = [var.tag_depends_on]
}

data "vsphere_tag_category" "category" {
  for_each   = local.tags_merged
  name       = each.value.cat
  depends_on = [var.tag_depends_on]
}

data "vsphere_tag" "tag" {
  for_each    = local.tags_merged
  name        = each.value.sub
  category_id = data.vsphere_tag_category.category[each.key].id
  depends_on  = [var.tag_depends_on]
}

data "vsphere_folder" "folder" {
  count      = var.vmfolder != null ? 1 : 0
  path       = "/${data.vsphere_datacenter.dc.name}/vm/${var.vmfolder}"
  depends_on = [var.vm_depends_on]
}

locals {
  interface_count     = length(var.ipv4submask) #Used for Subnet handeling
  template_disk_count = var.content_library == null ? length(data.vsphere_virtual_machine.template[0].disks) : 0
  tags_merged = merge([
    for key, values in var.tags : {
      for value in values :
      "${key}-${value}" => {
        "cat" = key
        "sub" = value
      }
    }
  ]...)
}

// Cloning a Linux or Windows VM from a given template.
resource "vsphere_virtual_machine" "vm" {
  count      = var.instances
  depends_on = [var.vm_depends_on]
  name       = var.staticvmname != null ? var.staticvmname : format("${var.vmname}${var.vmnameformat}", count.index + 1 + var.start_instance)

  resource_pool_id = data.vsphere_resource_pool.pool.id
  folder           = var.vmfolder
  tags             = var.tag_ids != null ? var.tag_ids : [for u in data.vsphere_tag.tag : u.id]

  custom_attributes       = var.custom_attributes
  annotation              = var.annotation
  extra_config            = var.extra_config
  firmware                = var.content_library == null && var.firmware == null ? data.vsphere_virtual_machine.template[0].firmware : var.firmware
  efi_secure_boot_enabled = var.content_library == null && var.efi_secure_boot == null ? data.vsphere_virtual_machine.template[0].efi_secure_boot_enabled : var.efi_secure_boot
  enable_disk_uuid        = var.content_library == null && var.enable_disk_uuid == null ? data.vsphere_virtual_machine.template[0].enable_disk_uuid : var.enable_disk_uuid
  storage_policy_id       = var.storage_policy_id

  datastore_cluster_id = var.datastore_cluster != "" ? data.vsphere_datastore_cluster.datastore_cluster[0].id : null
  datastore_id         = var.datastore != "" ? data.vsphere_datastore.datastore[0].id : null

  num_cpus               = var.cpu_number
  num_cores_per_socket   = var.num_cores_per_socket
  cpu_hot_add_enabled    = var.cpu_hot_add_enabled
  cpu_hot_remove_enabled = var.cpu_hot_remove_enabled
  cpu_reservation        = var.cpu_reservation
  cpu_share_level        = var.cpu_share_level
  cpu_share_count        = var.cpu_share_level == "custom" ? var.cpu_share_count : null
  memory_reservation     = var.memory_reservation
  memory                 = var.ram_size
  memory_hot_add_enabled = var.memory_hot_add_enabled
  memory_share_level     = var.memory_share_level
  memory_share_count     = var.memory_share_level == "custom" ? var.memory_share_count : null
  guest_id               = var.content_library == null ? data.vsphere_virtual_machine.template[0].guest_id : null
  scsi_bus_sharing       = var.scsi_bus_sharing
  scsi_type              = var.scsi_type != "" ? var.scsi_type : (var.content_library == null ? data.vsphere_virtual_machine.template[0].scsi_type : null)
  scsi_controller_count = max(
    max(0, flatten([
      for item in values(var.data_disk) : [
        for elem, val in item :
        elem == "data_disk_scsi_controller" ? val : 0
    ]])...) + 1,
    ceil((max(0, flatten([
      for item in values(var.data_disk) : [
        for elem, val in item :
        elem == "unit_number" ? val : 0
    ]])...) + 1) / 15),
  var.scsi_controller)
  wait_for_guest_net_routable = var.wait_for_guest_net_routable
  wait_for_guest_ip_timeout   = var.wait_for_guest_ip_timeout
  wait_for_guest_net_timeout  = var.wait_for_guest_net_timeout

  ignored_guest_ips = var.ignored_guest_ips

  dynamic "network_interface" {
    for_each = keys(var.network) #data.vsphere_network.network[*].id #other option
    content {
      network_id   = data.vsphere_network.network[network_interface.key].id
      adapter_type = var.network_type != null ? var.network_type[network_interface.key] : (var.content_library == null ? data.vsphere_virtual_machine.template[0].network_interface_types[0] : null)
    }
  }
  // Disks defined in the original template
  dynamic "disk" {
    for_each = var.content_library == null ? data.vsphere_virtual_machine.template[0].disks : []
    iterator = template_disks
    content {
      label             = length(var.disk_label) > 0 ? var.disk_label[template_disks.key] : "disk${template_disks.key}"
      size              = var.disk_size_gb != null ? var.disk_size_gb[template_disks.key] : data.vsphere_virtual_machine.template[0].disks[template_disks.key].size
      unit_number       = var.scsi_controller != null ? var.scsi_controller * 15 + template_disks.key : template_disks.key
      thin_provisioned  = data.vsphere_virtual_machine.template[0].disks[template_disks.key].thin_provisioned
      eagerly_scrub     = data.vsphere_virtual_machine.template[0].disks[template_disks.key].eagerly_scrub
      datastore_id      = var.disk_datastore != "" ? data.vsphere_datastore.disk_datastore[0].id : null
      storage_policy_id = length(var.template_storage_policy_id) > 0 ? var.template_storage_policy_id[template_disks.key] : null
      io_reservation    = length(var.io_reservation) > 0 ? var.io_reservation[template_disks.key] : null
      io_share_level    = length(var.io_share_level) > 0 ? var.io_share_level[template_disks.key] : "normal"
      io_share_count    = length(var.io_share_level) > 0 && var.io_share_level[template_disks.key] == "custom" ? var.io_share_count[template_disks.key] : null
    }
  }
  // Disk for template from Content Library
  dynamic "disk" {
    for_each = var.content_library == null ? [] : [1]
    iterator = template_disks
    content {
      label       = length(var.disk_label) > 0 ? var.disk_label[template_disks.key] : "disk${template_disks.key}"
      size        = var.disk_size_gb[template_disks.key]
      unit_number = var.scsi_controller != null ? var.scsi_controller * 15 + template_disks.key : template_disks.key
      // thin_provisioned  = data.vsphere_virtual_machine.template[0].disks[template_disks.key].thin_provisioned
      // eagerly_scrub     = data.vsphere_virtual_machine.template[0].disks[template_disks.key].eagerly_scrub
      datastore_id      = var.disk_datastore != "" ? data.vsphere_datastore.disk_datastore[0].id : null
      storage_policy_id = length(var.template_storage_policy_id) > 0 ? var.template_storage_policy_id[template_disks.key] : null
      io_reservation    = length(var.io_reservation) > 0 ? var.io_reservation[template_disks.key] : null
      io_share_level    = length(var.io_share_level) > 0 ? var.io_share_level[template_disks.key] : "normal"
      io_share_count    = length(var.io_share_level) > 0 && var.io_share_level[template_disks.key] == "custom" ? var.io_share_count[template_disks.key] : null
      disk_mode         = length(var.disk_mode) > 0 ? var.disk_mode[template_disks.key] : null
    }
  }
  // Additional disks defined by Terraform config
  dynamic "disk" {
    for_each = var.data_disk
    iterator = terraform_disks
    content {
      label = terraform_disks.key
      size  = lookup(terraform_disks.value, "size_gb", null)
      unit_number = (
        lookup(
          terraform_disks.value,
          "unit_number",
          -1
          ) < 0 ? (
          lookup(
            terraform_disks.value,
            "data_disk_scsi_controller",
            0
            ) > 0 ? (
            (terraform_disks.value.data_disk_scsi_controller * 15) +
            index(keys(var.data_disk), terraform_disks.key) +
            (var.scsi_controller == tonumber(terraform_disks.value["data_disk_scsi_controller"]) ? local.template_disk_count : 0)
            ) : (
            index(keys(var.data_disk), terraform_disks.key) + local.template_disk_count
          )
          ) : (
          tonumber(terraform_disks.value["unit_number"])
        )
      )
      thin_provisioned  = lookup(terraform_disks.value, "thin_provisioned", "true")
      eagerly_scrub     = lookup(terraform_disks.value, "eagerly_scrub", "false")
      datastore_id      = lookup(terraform_disks.value, "datastore_id", null)
      storage_policy_id = lookup(terraform_disks.value, "storage_policy_id", null)
      io_reservation    = lookup(terraform_disks.value, "io_reservation", null)
      io_share_level    = lookup(terraform_disks.value, "io_share_level", "normal")
      io_share_count    = lookup(terraform_disks.value, "io_share_level", null) == "custom" ? lookup(terraform_disks.value, "io_share_count") : null
      disk_mode         = lookup(terraform_disks.value, "disk_mode", null)
    }
  }
  clone {
    template_uuid = var.content_library == null ? data.vsphere_virtual_machine.template[0].id : data.vsphere_content_library_item.library_item_template[0].id
    linked_clone  = var.linked_clone
    timeout       = var.timeout

    customize {
      dynamic "linux_options" {
        for_each = var.is_windows_image ? [] : [1]
        content {
          host_name    = var.staticvmname != null ? var.staticvmname : format("${var.vmname}${var.vmnameformat}", count.index + 1)
          domain       = var.domain
          hw_clock_utc = var.hw_clock_utc
        }
      }

      dynamic "windows_options" {
        for_each = var.is_windows_image ? [1] : []
        content {
          computer_name         = format("${var.netbiosname}%1d", count.index + 1 + var.start_instance)
          admin_password        = var.local_adminpass
          workgroup             = var.workgroup
          join_domain           = var.windomain
          domain_admin_user     = var.domain_admin_user
          domain_admin_password = var.domain_admin_password
          organization_name     = var.orgname
          run_once_command_list = var.run_once
          auto_logon            = var.auto_logon
          auto_logon_count      = var.auto_logon_count
          time_zone             = var.time_zone
          product_key           = var.productkey
          full_name             = var.full_name
        }
      }

      dynamic "network_interface" {
        for_each = keys(var.network)
        content {
          ipv4_address = split("/", var.network[keys(var.network)[network_interface.key]][count.index])[0]
          ipv4_netmask = var.network[keys(var.network)[network_interface.key]][count.index] == "" ? null : (
            length(split("/", var.network[keys(var.network)[network_interface.key]][count.index])) == 2 ? (
              split("/", var.network[keys(var.network)[network_interface.key]][count.index])[1]
              ) : (
              length(var.ipv4submask) == 1 ? var.ipv4submask[0] : var.ipv4submask[network_interface.key]
            )
          )
        }
      }
      dns_server_list = var.dns_server_list
      dns_suffix_list = var.dns_suffix_list
      ipv4_gateway    = var.vmgateway
      timeout         = var.timeout
    }
  }

  // Advanced options
  hv_mode                          = var.hv_mode
  ept_rvi_mode                     = var.ept_rvi_mode
  nested_hv_enabled                = var.nested_hv_enabled
  enable_logging                   = var.enable_logging
  cpu_performance_counters_enabled = var.cpu_performance_counters_enabled
  swap_placement_policy            = var.swap_placement_policy
  latency_sensitivity              = var.latency_sensitivity

  shutdown_wait_timeout = var.shutdown_wait_timeout
  force_power_off       = var.force_power_off

  lifecycle {
    ignore_changes = [
      annotation,
      tools_upgrade_policy,
      host_system_id,
      #resource_pool_id,
      clone[0].template_uuid,
      clone[0].customize[0].dns_server_list,
      clone[0].customize[0].network_interface[0],
      clone[0].customize[0].timeout
    ]
  }
}
