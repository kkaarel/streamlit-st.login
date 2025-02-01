variable "resource_group_name" {
    type = string
    default = ""
}

variable "project" {
    type = string
    default = ""
}

variable "ARM_TENANT_ID" {
    type = string
    default = ""
  
}

variable "location" {
  type        = string
  description = "Default location of West Europe"
  default     = "West Europe"
}



variable "archive_file_streamlit" {
  type = string
  default = "./streamlit.zip"
  
}