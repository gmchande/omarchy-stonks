# Security

Stonks runs inside the Omarchy shell, unsandboxed, with your user's rights.

## Report a problem privately

Use the [Security tab's "Report a vulnerability"](https://github.com/gmchande/omarchy-stonks/security/advisories/new),
not an issue: issues are public. Say what you did, what Stonks did, and
which version you ran
(`jq -r .version ~/.config/omarchy/plugins/grvc.stonks/manifest.json`).

There's no set time for an answer.

## What counts

The README's [What it runs](https://github.com/gmchande/omarchy-stonks#what-it-runs) lists everything
Stonks does outside the shell: the commands it runs, the hosts it asks, and
the files it writes. A problem is anything that makes it go further: run
another command, or one of those with arguments it didn't choose; reach
another host; or write another file. So is anything that makes it read a
file other than those, its own, the shell's settings, and the theme's
colours. It counts the same whether it comes from a symbol, an answer from
Yahoo or Robinhood, or a data file.

A price or chart that's wrong isn't a security problem: use the
[bug form](https://github.com/gmchande/omarchy-stonks/issues/new?template=bug.yml).
