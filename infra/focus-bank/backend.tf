terraform {
  backend "s3" {
    # State lives in the pricepulse state bucket (us-east-1) under focus-bank/. Pass the bucket at
    # init time so the account id is not hardcoded:
    #   terraform -chdir=infra/focus-bank init -backend-config="bucket=pricepulse-tfstate-<acct>"
    key          = "focus-bank/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
