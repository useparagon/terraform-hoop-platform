import { GithubActionWorkflow } from '@useparagon/whiskers-core';

import { WorkflowInput } from '../whiskers.constants';
import { ReleaseJob } from '../job/release.job';

/**
 * Manual on purpose: every tag is a version consumers can pin, so a release is
 * a decision, not a side effect of merging.
 */
export default new GithubActionWorkflow({
  name: 'release',
  concurrency: {
    group: 'hoop-module-release',
    'cancel-in-progress': false,
  },
  on: {
    workflow_dispatch: {
      inputs: {
        [WorkflowInput.BUMP]: {
          description:
            'Version bump (semver). minor for new optional inputs, major for breaking changes.',
          type: 'choice',
          options: ['patch', 'minor', 'major'],
          default: 'minor',
        },
      },
    },
  },
  permissions: {
    contents: 'write',
    'pull-requests': 'read',
  },
  jobs: [new ReleaseJob()],
});
