variable "governance_account_id" {
  description = "Management or delegated-administrator account executing deployment"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.governance_account_id))
    error_message = "Provide the 12-digit governance account ID."
  }
}

variable "control_region" {
  description = "Region containing the StackSet and compliance aggregator"
  type        = string
  default     = "us-east-1"
}

variable "target_ou_ids" {
  description = "Organizational units whose member accounts receive these controls"
  type        = set(string)
  validation {
    condition     = length(var.target_ou_ids) > 0 && alltrue([for id in var.target_ou_ids : can(regex("^ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}$", id))])
    error_message = "Provide at least one valid AWS Organizations OU ID."
  }
}

variable "target_regions" {
  description = "Every Region containing buckets that should be governed"
  type        = set(string)
  default     = ["us-east-1"]
  validation {
    condition     = length(var.target_regions) > 0 && alltrue([for region in var.target_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "Provide at least one valid AWS Region name."
  }
}

variable "call_as" {
  description = "SELF for management account; DELEGATED_ADMIN for a registered StackSets administrator"
  type        = string
  default     = "SELF"
  validation {
    condition     = contains(["SELF", "DELEGATED_ADMIN"], var.call_as)
    error_message = "Use SELF or DELEGATED_ADMIN."
  }
}

variable "policy_prefix" {
  description = "Stable prefix for the StackSet, Config rule and remediation roles"
  type        = string
  default     = "account-governance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.policy_prefix))
    error_message = "Use 3-24 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "automatic_remediation" {
  description = "Automatically enable versioning on existing and future noncompliant buckets"
  type        = bool
  default     = true
}
