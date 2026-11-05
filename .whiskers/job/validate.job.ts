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
          name: 'terraform > checkov',
          uses: GithubAction.CHECKOV,
          with: {
            // The module and the workflows. secrets is empty here and would only add noise.
            framework: 'terraform,github_actions',
            directory: '.',
            quiet: 'true',
            compact: 'true',
          },
        }),
        new TerraformDocsStep(),
      ],
    });
  }
}
