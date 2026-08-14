# IAM role for model uploader job
data "aws_iam_policy_document" "model_uploader_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
    ]
  }
}

resource "aws_iam_role" "model_uploader" {
  name               = "${var.bucket_name}-uploader"
  assume_role_policy = data.aws_iam_policy_document.model_uploader_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.bucket_name}-uploader"
  })
}

data "aws_iam_policy_document" "model_uploader" {
  statement {
    sid       = "ListModelBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.model_storage.arn]
  }

  statement {
    sid    = "SynchronizeModelObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.model_storage.arn}/models/*"]
  }
}

resource "aws_iam_role_policy" "model_uploader" {
  name   = "${var.bucket_name}-uploader"
  role   = aws_iam_role.model_uploader.id
  policy = data.aws_iam_policy_document.model_uploader.json
}