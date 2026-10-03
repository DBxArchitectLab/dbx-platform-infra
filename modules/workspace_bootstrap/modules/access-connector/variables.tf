variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the access connector."
}
