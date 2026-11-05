import { execFileSync } from 'node:child_process';

import { nextVersion } from './version.ts';

/** Prints the next version from the commit messages passed as an argument, or nothing. */
function main(): void {
  const messages = process.argv[2] ?? '';
  const tags = execFileSync('git', ['tag', '--list', 'v*'], { encoding: 'utf8' })
    .split('\n')
    .filter((tag) => tag.length > 0);
  const version = nextVersion(tags, messages.split('\n\n').filter((message) => message.length > 0));
  if (version) {
    process.stdout.write(version);
  }
}

main();
