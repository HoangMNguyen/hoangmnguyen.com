terraform {
  backend "s3" {
    # State lives in the pricepulse state bucket under site/. Pass the bucket at init time so the
    # account id is not hardcoded:
    #   terraform -chdir=infra/bootstrap init -backend-config="bucket=pricepulse-tfstate-<acct>"
    key          = "site/bootstrap.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
