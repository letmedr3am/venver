# venver

Clone Git repositories (or use a local directory), create isolated Python
virtual environments, install dependencies automatically, and add shell
aliases for convenient command-line access.

## Features

- Clone or update Git repositories, or install from a local directory with `--local`
- Create a dedicated, **fully isolated** Python virtual environment for each tool
  (no reliance on system site-packages — everything needed is installed inside the venv)
- Automatically detect and rebuild older venvs that aren't isolated
- Automatically install dependencies from:
  - `pyproject.toml`
  - `setup.py`
  - `requirements.txt`
- Prefer an **editable install** (`pip install -e .`), matching the behavior of running
  that command yourself, with automatic fallback to a regular install if the
  package's build backend doesn't support it
- Optionally install an extras group (e.g. `.[dev]`, `.[all]`) with `--extras`
- Auto-detect the newest available `python3.x` interpreter in `PATH` if none is specified
- Detect common executable entry points
- Add or update aliases in your shell configuration
- Prompt after a successful install to add extra alias names for the same tool
- Support Python-based CLI tools and standalone scripts

## Requirements

- Git
- Bash
- Python 3 with `venv`
- `sudo` access when using the default `/opt/tools` directory

### Debian / Kali Installation

```bash
sudo apt update
sudo apt install -y git python3 python3-venv
```

## Usage

```bash
./venver [options] <git-repository-url>
./venver [options] --local <local-directory>
```

## Options

All options are optional.

| Option              | Description                                                                 |
|---------------------|-------------------------------------------------------------------------------|
| `--local PATH`      | Use a local directory instead of cloning a repository                        |
| `--tools-dir DIR`   | Repository root directory (default: `/opt/tools`; ignored with `--local`)    |
| `--python-bin BIN`  | Python interpreter (default: newest `python3.x` found in `PATH`)             |
| `--shell-rc FILE`   | Shell rc file to update (default: `~/.zshrc`)                                |
| `--alias NAME`      | Alias name (default: lowercase repository/directory name)                    |
| `--extras NAME`     | Install an optional-dependencies group (e.g. `dev`, `all`) if the repo is an installable package |
| `-h`, `--help`      | Show help                                                                    |

## Examples

```bash
./venver https://github.com/ly4k/Certipy

./venver https://github.com/AutoRecon/AutoRecon

./venver --python-bin python3.12 \
    https://github.com/fortra/impacket

./venver --tools-dir ~/tools --alias certipy-ad \
    https://github.com/ly4k/Certipy

./venver --extras dev https://github.com/some/tool

./venver --local ~/projects/mytool

./venver --local /opt/src/mytool --alias mytool
```

## How it works

1. **Source acquisition** — clones the repository into `--tools-dir` (or updates it
   with `git pull --ff-only` if already cloned), or validates the local directory
   given with `--local`.
2. **Python interpreter** — if `--python-bin` isn't given, venver scans `PATH` for
   every `python3.X` binary and picks the highest version found, falling back to a
   plain `python3` if none are versioned.
3. **Virtual environment** — created without system site-packages, so every
   dependency is installed inside the venv rather than resolved against
   packages already on the system. If an existing venv from an older, non-isolated
   run is detected, it's automatically rebuilt.
4. **Dependency installation**:
   - `pyproject.toml` or `setup.py` present → attempts an editable install
     (`pip install -e .`, optionally with `--extras` appended as `.[extras]`),
     falling back to a regular install if the backend doesn't support editable mode.
   - Only `requirements.txt` present → `pip install -r requirements.txt`.
   - None found → dependency installation is skipped with a warning.
5. **Executable detection** — looks for, in order: a venv script matching the
   alias name, `<alias>.py`, `<repo-name>.py`, then common entry points
   (`main.py`, `run.py`, `cli.py`, `<alias>.sh`), then any other executable in
   the venv's `bin/` directory.
6. **Alias management** — adds or updates an `alias` line in your shell rc file
   pointing to the detected executable.
7. **Extra aliases (optional)** — once installation succeeds, venver asks if
   you'd like additional alias names for the same command (comma-separated,
   e.g. `mtitl, toolong`). Each valid name gets its own alias in the shell rc
   file pointing to the same executable. This step is skipped automatically in
   non-interactive shells.

After a run, reload your shell configuration to use the new alias(es):

```bash
source ~/.zshrc
```
