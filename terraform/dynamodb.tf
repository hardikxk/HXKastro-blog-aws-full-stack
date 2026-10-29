# Single-table design: one table holds posts, comments and newsletter
# subscribers, distinguished by key prefix. On-demand billing so there's
# nothing to provision, and it sits comfortably inside DynamoDB's
# always-free allowance for demo-level traffic.
#
#   Post:        PK = POST#<postId>        SK = METADATA
#   Comment:      PK = POST#<postId>        SK = COMMENT#<commentId>
#   Subscriber:   PK = SUBSCRIBER           SK = <email>
resource "aws_dynamodb_table" "main" {
  name         = "${var.project_name}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }
  attribute {
    name = "SK"
    type = "S"
  }

  tags = { Project = var.project_name }
}
