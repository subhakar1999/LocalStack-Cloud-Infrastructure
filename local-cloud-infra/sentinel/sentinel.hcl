policy "required-tags" {
  source = "./required-tags.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "s3-protections" {
  source = "./s3-protections.sentinel"
  enforcement_level = "hard-mandatory"
}
