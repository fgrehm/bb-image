# Sudo and password setup

These changes are under [Unreleased](../CHANGELOG.md#unreleased); older pinned image tags retain their original sudo policy.

Every flavor installs sudo and initially grants `developer` passwordless administration. Standard container launches through Makefile still block elevation with `--security-opt no-new-privileges`. The `slim-sudo` and `full-sudo` compatibility profiles omit that flag; `SECURITY_OPTS=` explicitly permits elevation on a standard container image. Raw Docker/Podman launches must pass the flag themselves to block sudo, regardless of the tag. No `--privileged` flag is needed just to permit sudo. All VM flavors permit guest sudo from first boot.

Container/guest root can read stored credentials and resources deliberately shared into the environment. Avoid sensitive host mounts or host container-engine sockets in elevated environments.

## Set a password and require it for sudo

From an interactive shell as `developer`, in a VM or container whose launch policy permits sudo:

```bash
sudo bb-set-password
```

The account initially has a locked password, meaning password authentication is disabled, not that the account cannot run commands or use SSH keys. There is no shared initial password. Bare `passwd` cannot set the first password because it asks for a current password; bootstrap sudo lets the setup command call `passwd developer` as root without that deadlock.

The command sets the password with the native `passwd` prompts, validates sudoers, and retires the image's separate bootstrap `NOPASSWD` grant. The permanent grant requires a password. It clears cached sudo authentication for `developer`, but does not terminate existing root shells or already-running elevated commands. Repeating `sudo bb-set-password` lets you change the password, authenticating with the current one first.

**Ordinary `passwd` or `chpasswd` alone does not disable passwordless sudo.** Use the setup command for that transition. No PAM hook changes sudo policy automatically. The helper manages only the image's `developer` policy, not arbitrary accounts or customized grants. It rejects changes to its managed grants and detects a competing broad passwordless grant; administrator-added command-specific exceptions are outside its contract.

## Interactive reminders and suppression

Interactive bash/zsh terminals remind `developer` while the bootstrap passwordless grant exists, including when a password was set with ordinary `passwd` but bootstrap access was not retired. The reminder also explains when `no-new-privileges` blocks elevation. Noninteractive commands, root shells, and shells without a terminal stay quiet. Reminder logic lives in the image's system shell configuration, not the persistent home rc blocks.

For containers where you intentionally keep bootstrap access, set `BB_SUDO_REMINDER=0` in the deployment environment (for example, `podman run -e BB_SUDO_REMINDER=0 ...`). To silence it only for your user, run:

```bash
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/bb"
touch "${XDG_CONFIG_HOME:-$HOME/.config}/bb/sudo-reminder-disabled"
```

Both options silence only the reminder, not change sudo permissions. The marker normally lives in persistent home and survives container recreation; an environment override must be supplied again by the deployment. Remove the marker and unset the override to re-enable reminders. After `sudo bb-set-password` successfully retires bootstrap access, reminders stop without either suppression option.

## Failures and recovery

A failed or cancelled password change leaves sudo policy unchanged. Native `passwd` can ignore Ctrl-C at its password prompt; Ctrl-D (EOF) cancels it in the tested image. Password changes and sudoers changes are not one transaction: if policy verification fails after setting the password, the password may already have changed. When retiring bootstrap access fails verification, the helper attempts to restore the bootstrap grant, reports the problem, and exits nonzero. Keep an administrative session available, resolve the conflicting or invalid policy with `visudo`, then rerun `sudo bb-set-password`. If restoration itself fails, the error identifies the saved rule for recovery; do not close your root session until access is verified.

A successful `passwd` and stored password hash do not prove a customized PAM stack permits authentication. If you customize PAM or sudoers, test password-authenticated sudo while retaining an alternate administrative path.

Standard `no-new-privileges` containers cannot elevate to run this command. Choose an elevation-enabled launch profile deliberately; setting a password does not bypass launch restrictions. Host-side `podman exec --user root` is an operator recovery option for a container you own, not a reason to weaken normal launch policy.

## Persistence

Container passwords and sudo policy live under `/etc`, outside the home volume. Stop/start of the same container preserves them; recreation from the image resets to the locked account and bootstrap passwordless grant, even when reusing the same home volume. Provision password setup again if required; do not move shadow files into the home volume.

VM disk state preserves passwords and policy across restarts. Replacing a VM requires provisioning the policy again. exe.dev's actual login account still needs a live integration check: the grant is for `developer`, not an arbitrary platform-created account.
