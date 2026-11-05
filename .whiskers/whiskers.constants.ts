/** Pin actions by full commit SHA; the comment keeps the human version. */
export const GithubAction = {
  CHECKOUT: 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', // v7.0.1
  SETUP_TERRAFORM: 'hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd', // v3.1.2
  TERRAFORM_DOCS: 'terraform-docs/gh-actions@6de6da0cefcc6b4b7a5cbea4d79d97060733093c', // v1.4.1
  CHECKOV: 'bridgecrewio/checkov-action@a050c269d5ff0d9dc04f4826f3d268ace7b05592', // v12.1519.0
} as const;

export const TERRAFORM_VERSION = '1.14.8';

export enum JobId {
  VALIDATE = 'terraform',
  RELEASE = 'release',
}

export enum WorkflowInput {
  BUMP = 'bump',
}
