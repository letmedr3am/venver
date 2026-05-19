# venver

Clone Git repositories, create isolated Python virtual environments, install dependencies automatically, and add shell aliases for convenient command-line access.

## Features

- Clone or update Git repositories
- Create a dedicated Python virtual environment for each tool
- Automatically install dependencies from:
  - `pyproject.toml`
  - `setup.py`
  - `requirements.txt`
- Detect common executable entry points
- Add or update aliases in your shell configuration
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
