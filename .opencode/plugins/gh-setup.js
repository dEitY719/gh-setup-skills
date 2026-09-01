/**
 * gh-setup plugin for OpenCode.ai
 *
 * Auto-registers the skills directory via the config hook (no symlinks needed).
 *
 * Unlike superpowers, this plugin injects no per-session bootstrap context.
 * These are one-time repo-initialization skills — you reach for them when
 * standing up a new repo, not on every commit — so OpenCode's native `skill`
 * tool discovering them is all that is needed. Three of the four mutate a live
 * GitHub repo, which is a further reason not to keep them in the preamble.
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const GhSetupPlugin = async () => {
  const ghSetupSkillsDir = path.resolve(__dirname, '../../skills');

  return {
    // Inject skills path into live config so OpenCode discovers gh-setup skills
    // without requiring manual symlinks or config file edits.
    // This works because Config.get() returns a cached singleton — modifications
    // here are visible when skills are lazily discovered later.
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(ghSetupSkillsDir)) {
        config.skills.paths.push(ghSetupSkillsDir);
      }
    },
  };
};
