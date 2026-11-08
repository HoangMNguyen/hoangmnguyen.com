terraform {
  backend "s3" {
    # The state bucket is managed by this stack and also holds its state. Pass the bucket at init
    # time so the account id is not hardcoded:
    #   terraform -chdir=infra/account init -backend-config="bucket=pricepulse-tfstate-<acct>"
    key          = "account/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
