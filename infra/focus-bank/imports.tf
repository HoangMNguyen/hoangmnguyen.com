# These resources were first created by a CloudFormation stack (Focus-Bank, us-east-2) that was
# retired after Terraform adopted them. The blocks are no-ops once the resources are in state;
# they stay as the record of where each id came from.

import {
  to = aws_dynamodb_table.data
  id = "FocusBankData"
}

import {
  to = aws_cognito_identity_pool.main
  id = "us-east-2:05bc6bce-0739-49b9-8bfa-c35e3febdd6d"
}

import {
  to = aws_iam_role.this["guest"]
  id = "focusbank-guest-role"
}

import {
  to = aws_iam_role.this["user"]
  id = "focusbank-user-role"
}

import {
  to = aws_iam_role_policy.own_row_only["guest"]
  id = "focusbank-guest-role:own-row-only"
}

import {
  to = aws_iam_role_policy.own_row_only["user"]
  id = "focusbank-user-role:own-row-only"
}

import {
  to = aws_cognito_identity_pool_roles_attachment.main
  id = "us-east-2:05bc6bce-0739-49b9-8bfa-c35e3febdd6d"
}
