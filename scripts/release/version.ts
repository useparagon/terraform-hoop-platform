export type Bump = 'major' | 'minor' | 'patch' | 'none';

const STABLE_TAG = /^v(\d+\.\d+\.\d+)$/;
const HEADER_TYPE = /^([a-z]+)(?:\([^)]+\))?(!)?:/;

/** The bump a single conventional commit implies. Same rules agent-os uses. */
export function bumpFromCommitMessage(message: string): Bump {
  const normalized = message.replace(/\r\n/g, '\n');
  const firstLine = normalized.split('\n')[0] ?? '';
  const headerMatch = firstLine.match(HEADER_TYPE);

  if (/BREAKING CHANGE:/i.test(normalized) || headerMatch?.[2] === '!') {
    return 'major';
  }

  const type = headerMatch?.[1];
  if (type === 'feat') {
    return 'minor';
  }
  if (type === 'fix') {
    return 'patch';
  }

  return 'none';
}

export function strongestBump(bumps: Bump[]): Bump {
  if (bumps.includes('major')) return 'major';
  if (bumps.includes('minor')) return 'minor';
  if (bumps.includes('patch')) return 'patch';
  return 'none';
}

export function applyBump(version: string, bump: Bump): string {
  const [major = 0, minor = 0, patch = 0] = version.split('.').map(Number);
  if (bump === 'major') return `${major + 1}.0.0`;
  if (bump === 'minor') return `${major}.${minor + 1}.0`;
  if (bump === 'patch') return `${major}.${minor}.${patch + 1}`;
  return version;
}

export function latestStableVersion(tags: string[]): string | undefined {
  return tags
    .map((tag) => tag.match(STABLE_TAG)?.[1])
    .filter((version): version is string => version !== undefined)
    .sort(compareSemver)
    .at(-1);
}

export function compareSemver(left: string, right: string): number {
  const [l, r] = [left, right].map((version) => version.split('.').map(Number));
  for (let index = 0; index < 3; index += 1) {
    const delta = (l[index] ?? 0) - (r[index] ?? 0);
    if (delta !== 0) return delta;
  }
  return 0;
}

/**
 * Next stable version from the commits since the latest tag.
 * No tag yet starts at 0.0.0, so the first release becomes v0.1.0.
 * undefined means nothing releasable landed since the last tag.
 */
export function nextVersion(tags: string[], commitMessages: string[]): string | undefined {
  const bump = strongestBump(commitMessages.map(bumpFromCommitMessage));
  if (bump === 'none') return undefined;

  const latest = latestStableVersion(tags);
  return applyBump(latest ?? '0.0.0', bump);
}
