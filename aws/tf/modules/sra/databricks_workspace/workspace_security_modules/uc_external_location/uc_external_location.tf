resource "null_resource" "previous" {}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [null_resource.previous]

  create_duration = "30s"
}

// Storage Credential Trust Policy
data "aws_iam_policy_document" "passrole_for_storage_credential" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"]
      type        = "AWS"
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
  statement {
    sid     = "ExplicitSelfRoleAssumption"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:root"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.aws_account_id}:role/${var.resource_prefix}-storage-credential"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.databricks_account_id]
    }
  }
}

// Storage Credential Role
resource "aws_iam_role" "storage_credential_role" {
  name               = "${var.resource_prefix}-storage-credential"
  assume_role_policy = data.aws_iam_policy_document.passrole_for_storage_credential.json
  permissions_boundary = "arn:aws:iam::${var.aws_account_id}:policy/cloudboost_account_operator_boundary_policy"
  tags = {
    Name = "${var.resource_prefix}-storage_credential_role"
  }
}


// Storage Credential Policy
resource "aws_iam_role_policy" "storage_credential_policy" {
  name = "${var.resource_prefix}-storage-credential-policy"
  role = aws_iam_role.storage_credential_role.id
  policy = jsonencode({ Version : "2012-10-17",
    Statement : [
      {
        "Action" : [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetLifecycleConfiguration",
        ],
        "Resource" : [
          "arn:aws:s3:::${var.data_bucket}/*",
          "arn:aws:s3:::${var.data_bucket}"
        ],
        "Effect" : "Allow"
      },
      {
        "Action" : [
          "sts:AssumeRole"
        ],
        "Resource" : [
          "arn:aws:iam::${var.aws_account_id}:role/${var.resource_prefix}-storage-credential"
        ],
        "Effect" : "Allow"
      }
    ]
    }
  )
}

// Storage Credential
resource "databricks_storage_credential" "external" {
  name = aws_iam_role.storage_credential_role.name
  aws_iam_role {
    role_arn = aws_iam_role.storage_credential_role.arn
  }
  depends_on = [aws_iam_role.storage_credential_role, time_sleep.wait_30_seconds]
}

// External Location
resource "databricks_external_location" "data_example" {
  name            = "external-location-example"
  url             = "s3://${var.data_bucket}/"
  credential_name = databricks_storage_credential.external.id
  skip_validation = true
  read_only       = true
  comment         = "Managed by TF"
}

// External Location Grant
resource "databricks_grants" "data_example" {
  external_location = databricks_external_location.data_example.id
  grant {
    principal  = var.data_access_user
    privileges = ["ALL_PRIVILEGES"]
  }
}