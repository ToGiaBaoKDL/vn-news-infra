data "oci_identity_availability_domains" "home" {
  compartment_id = var.tenancy_ocid
}
