import { GithubActionWorkflowJob, GithubActionWorkflowStep, wrap } from '@useparagon/whiskers-core';

import { GithubAction, JobId, WorkflowInput } from '../whiskers.constants';
import { SetupTerraformStep, TerraformCheckStep } from '../step/terraform/terraform.step';

/**
 * Every tag is a version consumers pin, so a release is a manual decision.
 * The same checks as validate run first; a failing check never produces a tag.
 */
export class ReleaseJob extends GithubActionWorkflowJob {
  constructor() {
    super({
      id: JobId.RELEASE,
      name: 'release',
      if: "github.ref == 'refs/heads/main'",
      'runs-on': 'ubuntu-latest',
      permissions: {
        contents: 'write',
        'pull-requests': 'read',
      },
      steps: [
        new GithubActionWorkflowStep({
          name: 'git > checkout',
          uses: GithubAction.CHECKOUT,
          with: { ref: 'main' },
        }),
        new SetupTerraformStep(),
        new TerraformCheckStep('fmt'),
        new TerraformCheckStep('init'),
        new TerraformCheckStep('validate'),
        new TerraformCheckStep('test'),
        new GithubActionWorkflowStep({
          name: 'release > create',
          uses: GithubAction.RELEASE,
          env: { GITHUB_TOKEN: wrap('github.token') },
          with: {
            bump_version_scheme: wrap(`inputs.${WorkflowInput.BUMP}`),
            tag_prefix: 'v',
            use_github_release_notes: 'true',
          },
        }),
      ],
    });
  }
}
