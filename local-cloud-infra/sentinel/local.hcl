sentinel {
  features = { terraform = true }
}

import "plugin" "tfplan/v2" {
  config = { plan_path = "../terraform/policy.tfplan.json" }
}
