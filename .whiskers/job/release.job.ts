import { GithubActionWorkflowJob, GithubActionWorkflowStep } from '@useparagon/whiskers-core';

import { GithubAction, JobId } from '../whiskers.constants';
import { SetupTerraformStep, TerraformCheckStep } from '../step/terraform/terraform.step';

/**
 * A release is a manual decision. The version comes from the commits since the
 * last stable tag (feat = minor, fix = patch, breaking = major), the same rules
 * agent-os uses, so the workflow takes no inputs. Nothing releasable means no tag.
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
      },
      steps: [
        new GithubActionWorkflowStep({
          name: 'git > checkout',
          uses: GithubAction.CHECKOUT,
          with: { ref: 'main', 'fetch-depth': '0' },
        }),
        new SetupTerraformStep(),
        new TerraformCheckStep('fmt'),
        new TerraformCheckStep('init'),
        new TerraformCheckStep('validate'),
        new TerraformCheckStep('test'),
        new GithubActionWorkflowStep({
          id: 'version',
          name: 'release > version',
          run: [
            'git fetch --tags --force',
            'range=$(git describe --tags --abbrev=0 --match "v[0-9]*" 2>/dev/null || git rev-list --max-parents=0 HEAD)',
            'messages=$(git log --format=%B "$range"..HEAD)',
            'version=$(node --experimental-strip-types scripts/release/cli.ts "$messages")',
            'echo "version=$version" >> "$GITHUB_OUTPUT"',
            'echo "skip=$([ -z "$version" ] && echo true || echo false)" >> "$GITHUB_OUTPUT"',
          ].join('\n'),
        }),
        new GithubActionWorkflowStep({
          name: 'release > tag',
          if: "steps.version.outputs.skip != 'true'",
          run: 'gh release create "v${{ steps.version.outputs.version }}" --target main --generate-notes --title "v${{ steps.version.outputs.version }}"',
          env: { GH_TOKEN: '${{ github.token }}' },
        }),
      ],
    });
  }
}
