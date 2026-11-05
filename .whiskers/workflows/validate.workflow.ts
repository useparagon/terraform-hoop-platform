import { GithubActionWorkflow } from '@useparagon/whiskers-core';

import { ValidateJob } from '../job/validate.job';

/** Checks formatting, validity, tests and README freshness on every pull request. */
export default new GithubActionWorkflow({
  name: 'validate',
  on: {
    push: { branches: ['main'] },
    pull_request: {},
    workflow_dispatch: {},
  },
  permissions: { contents: 'read' },
  jobs: [new ValidateJob()],
});
