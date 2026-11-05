import { GithubActionWorkflowStep } from '@useparagon/whiskers-core';

import { GithubAction, TERRAFORM_VERSION } from '../../whiskers.constants';

/** Shared Terraform steps so validate and release run exactly the same checks. */
export class SetupTerraformStep extends GithubActionWorkflowStep {
  constructor() {
    super({
      name: 'terraform > setup',
      uses: GithubAction.SETUP_TERRAFORM,
      with: { terraform_version: TERRAFORM_VERSION },
    });
  }
}

export class TerraformCheckStep extends GithubActionWorkflowStep {
  constructor(command: 'fmt' | 'init' | 'validate' | 'test') {
    const run = {
      fmt: 'terraform fmt -check -recursive',
      init: 'terraform init -backend=false -input=false',
      validate: 'terraform validate',
      test: 'terraform test -no-color',
    }[command];

    super({ name: `terraform > ${command}`, run });
  }
}

/** Fails when the committed README drifts from the generated terraform-docs output. */
export class TerraformDocsStep extends GithubActionWorkflowStep {
  constructor() {
    super({
      name: 'terraform > verify README',
      uses: GithubAction.TERRAFORM_DOCS,
      with: {
        'working-dir': '.',
        'output-file': 'README.md',
        'output-method': 'inject',
        'fail-on-diff': 'true',
        // Provider versions follow whatever init resolved, which would make the diff flaky.
        args: '--hide providers',
      },
    });
  }
}
