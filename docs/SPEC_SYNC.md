# Bringing a Claude export into GitHub

Claude is for review. GitHub is the copy the build uses. When Claude has a newer pack, export it and attach the zip. Do not paste the files into chat.

## Export

1. Open the CanDo project in Claude.
2. Use the project's export (download the project files as a zip). Include the docs, rules, schema, tests and stories. Leave out secrets, `.env` files, and database passwords.
3. Keep the zip. The file name can stay as Claude saved it.

## Attach it

Start a cloud agent on https://github.com/waelhusseinhr/CanDoHR and attach the zip to that run. The agent unpacks it in the cloud. It does not use your PC, and it does not ask you to type a device code.

The branch name for a fresh export looks like `cursor/spec-from-claude-export-4cf6`. The same shape, with a new short ending, is the one to use the next time. Open a pull request from that branch. Do not push the zip onto `main` by itself.

## What the agent should do with the zip

- Copy changed product docs into `docs/` and the matching spec mirror.
- Leave secrets out of the commit.
- Do not overwrite a migration that has already been applied. New database changes are new files.
- Say which docs changed, in plain language, in the pull request.
