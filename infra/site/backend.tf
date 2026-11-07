terraform {
  backend "s3" {
    # Shares the pricepulse state bucket under site/. Pass the bucket at init time so the account id
    # is not hardcoded:
    #   terraform -chdir=infra/site init -backend-config="bucket=pricepulse-tfstate-<acct>"
    key          = "site/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
