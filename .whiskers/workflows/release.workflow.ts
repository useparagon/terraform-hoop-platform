import { GithubActionWorkflow } from '@useparagon/whiskers-core';

import { ReleaseJob } from '../job/release.job';

/**
 * Manual on purpose: every tag is a version consumers can pin, so a release is
 * a decision, not a side effect of merging. The version is computed from the
 * commits, so the workflow takes no inputs.
 */
export default new GithubActionWorkflow({
  name: 'release',
  concurrency: {
    group: 'hoop-module-release',
    'cancel-in-progress': false,
  },
  on: {
    workflow_dispatch: {},
  },
  permissions: {
    contents: 'write',
  },
  jobs: [new ReleaseJob()],
});
