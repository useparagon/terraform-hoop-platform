import assert from 'node:assert/strict';
import test from 'node:test';

import { nextVersion } from './version.ts';

test('the first release is a minor bump from 0.0.0', () => {
  assert.equal(nextVersion([], ['feat: add the module']), '0.1.0');
});

test('a feature bumps the minor and resets the patch', () => {
  assert.equal(nextVersion(['v0.1.0', 'v0.1.1'], ['feat: add redis']), '0.2.0');
});

test('a fix bumps only the patch', () => {
  assert.equal(nextVersion(['v1.2.3'], ['fix: token wait']), '1.2.4');
});

test('a breaking change wins over features and fixes', () => {
  assert.equal(
    nextVersion(['v1.4.2'], ['fix: typo', 'feat!: drop the connections input']),
    '2.0.0',
  );
});

test('a breaking footer is a major bump', () => {
  assert.equal(
    nextVersion(['v1.0.0'], ['feat: rename input\n\nBREAKING CHANGE: the old name is gone']),
    '2.0.0',
  );
});

test('chore and docs commits release nothing', () => {
  assert.equal(nextVersion(['v1.0.0'], ['chore: regen docs', 'docs: fix typo']), undefined);
});

test('pre-release tags are ignored', () => {
  assert.equal(nextVersion(['v1.0.0', 'v1.1.0-beta.1'], ['fix: wait']), '1.0.1');
});
