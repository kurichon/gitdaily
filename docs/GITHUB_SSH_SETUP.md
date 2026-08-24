# GitHub SSH setup before cloning

The daily service is intentionally non-interactive. It must be able to fetch and push without asking for a GitHub password, PAT, SSH-key passphrase, or unknown-host confirmation.

## First: do not clone with `sudo`

Run Git and SSH as the normal Linux account that will own the repository and run the service. A key created under `~/.ssh` for your normal account is not the same key root sees under `/root/.ssh`.

Check existing GitHub SSH authentication:

```bash
ssh -T git@github.com
```

A successful GitHub authentication prints a message identifying the account and normally exits with status 1 because GitHub does not provide shell access. `Permission denied (publickey)` means GitHub did not accept an available SSH key.

## Recommended for this automation: repository-scoped deploy key

A dedicated deploy key limits this Linux machine to this repository instead of giving an unattended key access to every repository on your GitHub account.

Generate a dedicated Ed25519 key as your normal Linux user:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/gitdaily_ed25519 -C "gitdaily@$(hostname)" -N ''
chmod 600 ~/.ssh/gitdaily_ed25519
chmod 644 ~/.ssh/gitdaily_ed25519.pub
```

Display the public key:

```bash
cat ~/.ssh/gitdaily_ed25519.pub
```

On GitHub, open the `gitdaily` repository, then go to **Settings → Deploy keys → Add deploy key**. Paste the public key and enable **Allow write access**. The private key stays only on the Linux machine.

Configure a dedicated SSH host alias:

```bash
cat >> ~/.ssh/config <<'EOF_SSH'

Host github-gitdaily
    HostName github.com
    User git
    IdentityFile ~/.ssh/gitdaily_ed25519
    IdentitiesOnly yes
EOF_SSH
chmod 600 ~/.ssh/config
```

Test it:

```bash
ssh -T git@github-gitdaily
```

On the first connection, SSH may ask you to verify GitHub's host key. Compare the fingerprint against GitHub's published SSH fingerprints before accepting it. After the host is trusted and the deploy key has been added, the test should identify the authenticated repository/account instead of reporting `Permission denied (publickey)`.

Now clone **without sudo**:

```bash
git clone git@github-gitdaily:YOUR_GITHUB_USERNAME/gitdaily.git ~/gitdaily
cd ~/gitdaily
```

Verify both read and write authorization:

```bash
GIT_TERMINAL_PROMPT=0 git fetch origin main
GIT_TERMINAL_PROMPT=0 git push --dry-run origin main
```

Only after those commands succeed should you run:

```bash
sudo bash ./install.sh
```

## If you already have a suitable GitHub SSH key

You do not need a second key. If this succeeds non-interactively:

```bash
ssh -T git@github.com
```

and your key does not depend on a desktop-only `ssh-agent`, clone normally:

```bash
git clone git@github.com:YOUR_GITHUB_USERNAME/gitdaily.git ~/gitdaily
```

## Public-repository bootstrap

A public repository can be cloned over HTTPS without authentication if you only need to get the files onto Linux:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/gitdaily.git ~/gitdaily
```

Before installation, configure SSH and replace the remote because the service intentionally rejects unattended HTTPS remotes:

```bash
cd ~/gitdaily
git remote set-url origin git@github-gitdaily:YOUR_GITHUB_USERNAME/gitdaily.git
GIT_TERMINAL_PROMPT=0 git push --dry-run origin main
```
