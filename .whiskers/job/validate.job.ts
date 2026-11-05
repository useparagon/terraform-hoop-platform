import { GithubActionWorkflowJob, GithubActionWorkflowStep } from '@useparagon/whiskers-core';

import { GithubAction, JobId } from '../whiskers.constants';
import {
  SetupTerraformStep,
  TerraformCheckStep,
  TerraformDocsStep,
} from '../step/terraform/terraform.step';

export class ValidateJob extends GithubActionWorkflowJob {
  constructor() {
    super({
      id: JobId.VALIDATE,
      name: 'terraform',
      'runs-on': 'ubuntu-latest',
      steps: [
        new GithubActionWorkflowStep({
          name: 'git > checkout',
          uses: GithubAction.CHECKOUT,
        }),
        new SetupTerraformStep(),
        new TerraformCheckStep('fmt'),
        new TerraformCheckStep('init'),
        new TerraformCheckStep('validate'),
        new TerraformCheckStep('test'),
        new GithubActionWorkflowStep({
          name: 'python > setup',
          uses: GithubAction.SETUP_PYTHON,
          with: { 'python-version': '3.12' },
        }),
        new GithubActionWorkflowStep({
          // The checkov-action bundles Checkov 2, which cannot scan two frameworks at once.
          name: 'terraform > checkov',
          run: 'pip install checkov==3.4.3 && checkov -d . --framework terraform github_actions --quiet --compact',
        }),
        new TerraformDocsStep(),
      ],
    });
  }
}
