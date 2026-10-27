# Security

Stonks runs inside the Omarchy shell, with no sandbox and the same
permissions as your account.

## Report a problem privately

Use the [Security tab's "Report a vulnerability"](https://github.com/gmchande/omarchy-stonks/security/advisories/new),
not an issue: issues are public. Say what you did, what Stonks did, and
which version you ran
(`jq -r .version ~/.config/omarchy/plugins/grvc.stonks/manifest.json`).

There's no set time for an answer.

## What counts

The README's [What it runs](https://github.com/gmchande/omarchy-stonks#what-it-runs)
lists the commands Stonks runs, the sites it asks, and the files it
writes. It's a security problem if anything can make Stonks:

- run another command, or one of its own with arguments it didn't choose;
- contact another site;
- write another file;
- read any file other than the ones it writes, its own files, the shell's
  settings, the theme's colors, and the Omasnap and Pictures folder
  settings that say where screenshots go.

It counts whether it comes from a symbol, an answer from Yahoo or
Robinhood, or a data file.

A price or chart that's wrong isn't a security problem: use the
[bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
