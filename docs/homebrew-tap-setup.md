# Setting up the Homebrew tap

Internal guide for publishing `claude-project-profile` via Homebrew.

## How it works

Homebrew taps require a separate repo named `homebrew-<name>`. Users run:

```bash
brew tap yarikleto/claude-project-profile    # clones yarikleto/homebrew-claude-project-profile
brew install claude-project-profile          # installs from the formula in that repo
```

The tap repo contains a single formula file that points to a release tarball in the main `claude-project-profile` repo. Homebrew downloads the source from the main repo, not from the tap.

## Step 1: Create a release tag

```bash
# In the claude-project-profile repo
git tag v1.0.0
git push origin v1.0.0
```

## Step 2: Get the tarball SHA256

```bash
curl -sL https://github.com/yarikleto/claude-project-profile/archive/refs/tags/v1.0.0.tar.gz \
  | shasum -a 256
```

Save the hash — you'll need it for the formula.

## Step 3: Create the tap repo

Create a new GitHub repo: `yarikleto/homebrew-claude-project-profile`

```bash
mkdir homebrew-claude-project-profile
cd homebrew-claude-project-profile
git init
mkdir Formula
```

## Step 4: Add the formula

Create `Formula/claude-project-profile.rb`:

```ruby
class ClaudeProjectProfile < Formula
  desc "Switch between Claude Code project-level configuration profiles"
  homepage "https://github.com/yarikleto/claude-project-profile"
  url "https://github.com/yarikleto/claude-project-profile/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256_FROM_STEP_2"
  license "MIT"

  depends_on "bash"

  def install
    # Install supporting modules to libexec (Homebrew's private dir for the formula)
    libexec.install "lib", "commands"

    # Install main script and patch SCRIPT_DIR to find modules in libexec
    bin.install "claude-project-profile"
    inreplace bin/"claude-project-profile",
      /^SCRIPT_DIR=.*/, "SCRIPT_DIR=\"#{libexec}\""

    # Install shell completions (Homebrew links these automatically)
    zsh_completion.install "completions/_claude-project-profile"
    bash_completion.install "completions/claude-project-profile.bash" => "claude-project-profile"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/claude-project-profile version")
  end
end
```

What the formula does:

1. **Downloads** the tagged tarball from the main repo
2. **Installs `lib/` and `commands/`** to `libexec` — Homebrew's standard location for internal files that shouldn't be in PATH (`$(brew --prefix)/Cellar/claude-project-profile/1.0.0/libexec/`)
3. **Installs `claude-project-profile`** to `bin` — Homebrew symlinks this into PATH (`$(brew --prefix)/bin/`)
4. **Patches `SCRIPT_DIR`** — replaces the line `SCRIPT_DIR="$(cd ...)"` with a hardcoded path to `libexec`, so the installed binary finds its modules
5. **Installs completions** — Homebrew has built-in helpers (`zsh_completion`, `bash_completion`) that put files in the right place and make them discoverable automatically. No manual PATH or `fpath` setup needed.

The resulting file layout:

```
$(brew --prefix)/
├── bin/
│   └── claude-project-profile -> ../Cellar/claude-project-profile/1.0.0/bin/claude-project-profile
├── Cellar/claude-project-profile/1.0.0/
│   ├── bin/claude-project-profile           # Patched: SCRIPT_DIR points to libexec
│   └── libexec/
│       ├── lib/
│       │   ├── config.sh
│       │   ├── includes.sh
│       │   ├── output.sh
│       │   ├── state.sh
│       │   ├── files.sh
│       │   └── git.sh
│       └── commands/
│           ├── profile.sh
│           ├── info.sh
│           ├── history.sh
│           └── ui.sh
├── share/zsh/site-functions/
│   └── _claude-project-profile              # zsh completions (auto-discovered)
└── etc/bash_completion.d/
    └── claude-project-profile               # bash completions (auto-discovered)
```

## Step 5: Push the tap repo

```bash
cd homebrew-claude-project-profile
git add Formula/claude-project-profile.rb
git commit -m "claude-project-profile 1.0.0"
git remote add origin git@github.com:yarikleto/homebrew-claude-project-profile.git
git push -u origin main
```

## Step 6: Test

```bash
brew tap yarikleto/claude-project-profile
brew install claude-project-profile
claude-project-profile version   # should print "claude-project-profile 1.0.0"
```

## Releasing a new version

1. Update `VERSION` in `lib/config.sh` to match the new tag.

2. Commit, tag, and push in the main repo:
   ```bash
   git add lib/config.sh
   git commit -m "Bump version to 1.1.0"
   git tag v1.1.0
   git push origin main --tags
   ```

3. Get the new SHA256:
   ```bash
   curl -sL https://github.com/yarikleto/claude-project-profile/archive/refs/tags/v1.1.0.tar.gz \
     | shasum -a 256
   ```

4. Update the formula in the tap repo — change `url` and `sha256`:
   ```ruby
   url "https://github.com/yarikleto/claude-project-profile/archive/refs/tags/v1.1.0.tar.gz"
   sha256 "NEW_SHA256_HERE"
   ```

5. Commit and push the tap repo.

6. Users upgrade with:
   ```bash
   brew update && brew upgrade claude-project-profile
   ```
   `brew update` is needed to fetch the latest formula from the tap repo.

## Automating releases (optional)

Add a GitHub Actions workflow to the main repo that automatically updates the tap formula on new tags. See [homebrew-releaser](https://github.com/Justintime50/homebrew-releaser) or write a simple workflow:

```yaml
# .github/workflows/update-homebrew.yml
name: Update Homebrew formula
on:
  push:
    tags: ['v*']
jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Update formula
        env:
          TAP_REPO_TOKEN: ${{ secrets.TAP_REPO_TOKEN }}
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          SHA=$(curl -sL "https://github.com/yarikleto/claude-project-profile/archive/refs/tags/${TAG}.tar.gz" | sha256sum | cut -d' ' -f1)
          git clone https://x-access-token:${TAP_REPO_TOKEN}@github.com/yarikleto/homebrew-claude-project-profile.git tap
          cd tap
          sed -i "s|url \".*\"|url \"https://github.com/yarikleto/claude-project-profile/archive/refs/tags/${TAG}.tar.gz\"|" Formula/claude-project-profile.rb
          sed -i "s|sha256 \".*\"|sha256 \"${SHA}\"|" Formula/claude-project-profile.rb
          git add Formula/claude-project-profile.rb
          git commit -m "Update to ${TAG}"
          git push
```

This requires a `TAP_REPO_TOKEN` secret with write access to the tap repo.
