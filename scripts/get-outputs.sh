#!/usr/bin/env bash
# Lee `terraform output` y lo exporta a GITHUB_ENV (usado por los workflows)
set -euo pipefail
cd "$(dirname "$0")/../environments/dev"
{
  echo "AWS_REGION=us-east-1"
  echo "ACCOUNT_ID=$(terraform output -raw account_id)"
  echo "CLUSTER_NAME=$(terraform output -raw cluster_name)"
  echo "VPC_ID=$(terraform output -raw vpc_id)"
  echo "ALB_SG_ID=$(terraform output -raw alb_sg_id)"
  echo "RDS_ENDPOINT=$(terraform output -raw db_address)"
  echo "ASG_NAME=$(terraform output -raw node_group_asg_name)"
} >> "$GITHUB_ENV"
