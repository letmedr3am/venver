#!/usr/bin/env bash
#
# venver
#
# Clone a Python-based Git repository, create an isolated virtual
# environment, install dependencies, and add/update an alias in ~/.zshrc.
#
# Supported repository layouts:
#   1. pyproject.toml or setup.py  -> python -m pip install <repo>
#   2. requirements.txt only      -> python -m pip install -r requirements.txt
#   3. Standalone *.py scripts    -> alias runs the script with the venv Python
#
# Usage:
#   ./venver [options] <git-repository-url>
#
# Options (all optional):
#   --tools-dir DIR     Repository root directory (default: /opt/tools)
#   --python-bin BIN    Python interpreter (default: python3.13)
#   --shell-rc FILE     Shell rc file to update (default: ~/.zshrc)
#   --alias NAME        Alias name (default: lowercase repository name)
#   -h, --help          Show this help
#
# Examples:
#   ./venver https://github.com/ly4k/Certipy
#   ./venver https://github.com/AutoRecon/AutoRecon
#   ./venver --python-bin python3.12 \
#       https://github.com/fortra/impacket
#   ./venver --tools-dir ~/tools --alias certipy-ad \
#       https://github.com/ly4k/Certipy

set -euo pipefail

# -----------------------------------------------------------------------------
# Default configuration
# -----------------------------------------------------------------------------

TOOLS_DIR="/opt/tools"
PYTHON_BIN="python3.13"
SHELL_RC="${HOME}/.zshrc"
ALIAS_NAME=""
REPO_URL=""

readonly SCRIPT_NAME="venver"

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------

log() {
    local level="$1"
    shift

    local timestamp
    timestamp="$(date '+%H:%M:%S')"

    printf '[%s] %-7s %s\n' "$timestamp" "$level" "$*" >&2
}

info()    { log INFO    "$@"; }
warn()    { log WARN    "$@"; }
error()   { log ERROR   "$@"; }
success() { log SUCCESS "$@"; }

die() {
    error "$@"
    exit 1
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options] <git-repository-url>

Clone a Python-based Git repository, create an isolated virtual environment,
install dependencies, and add/update an alias in your shell configuration.

Options (all optional):
  --tools-dir DIR     Repository root directory (default: ${TOOLS_DIR})
  --python-bin BIN    Python interpreter (default: ${PYTHON_BIN})
  --shell-rc FILE     Shell rc file to update (default: ${SHELL_RC})
  --alias NAME        Alias name (default: lowercase repository name)
  -h, --help          Show this help

Examples:
  ${SCRIPT_NAME} https://github.com/ly4k/Certipy
  ${SCRIPT_NAME} https://github.com/AutoRecon/AutoRecon
  ${SCRIPT_NAME} --python-bin python3.12 \\
      https://github.com/fortra/impacket
  ${SCRIPT_NAME} --tools-dir ~/tools --alias certipy-ad \\
      https://github.com/ly4k/Certipy
EOF
}

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

cleanup() {
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        success "Installation completed successfully."
    else
        error "Installation failed (exit code: ${exit_code})."
    fi
}

trap cleanup EXIT

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tools-dir)
            [[ $# -ge 2 ]] || die "Missing value for --tools-dir"
            TOOLS_DIR="$2"
            shift 2
            ;;
        --python-bin)
            [[ $# -ge 2 ]] || die "Missing value for --python-bin"
            PYTHON_BIN="$2"
            shift 2
            ;;
        --shell-rc)
            [[ $# -ge 2 ]] || die "Missing value for --shell-rc"
            SHELL_RC="$2"
            shift 2
            ;;
        --alias)
            [[ $# -ge 2 ]] || die "Missing value for --alias"
            ALIAS_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            if [[ -n "$REPO_URL" ]]; then
                die "Only one repository URL may be specified."
            fi
            REPO_URL="$1"
            shift
            ;;
    esac
done

if [[ -z "$REPO_URL" ]]; then
    usage >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Expand paths
# -----------------------------------------------------------------------------

TOOLS_DIR="${TOOLS_DIR/#\~/$HOME}"
SHELL_RC="${SHELL_RC/#\~/$HOME}"

# -----------------------------------------------------------------------------
# Derived values
# -----------------------------------------------------------------------------

REPO_NAME="$(basename -s .git "$REPO_URL")"
REPO_DIR="${TOOLS_DIR}/${REPO_NAME}"
VENV_DIR="${REPO_DIR}/venv"

if [[ -z "$ALIAS_NAME" ]]; then
    ALIAS_NAME="$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')"
fi

# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || die "git is not installed."
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "Python interpreter not found: ${PYTHON_BIN}"

# -----------------------------------------------------------------------------
# Configuration summary
# -----------------------------------------------------------------------------

info "Repository URL : ${REPO_URL}"
info "Repository     : ${REPO_NAME}"
info "Tools dir      : ${TOOLS_DIR}"
info "Python bin     : ${PYTHON_BIN}"
info "Shell RC       : ${SHELL_RC}"
info "Alias          : ${ALIAS_NAME}"

# -----------------------------------------------------------------------------
# Ensure tools directory exists and is writable
# -----------------------------------------------------------------------------

info "Ensuring tools directory exists"
sudo mkdir -p "$TOOLS_DIR"
sudo chown -R "$USER:$USER" "$TOOLS_DIR"

# -----------------------------------------------------------------------------
# Clone or update repository
# -----------------------------------------------------------------------------

if [[ -d "${REPO_DIR}/.git" ]]; then
    info "Updating repository"
    git -C "$REPO_DIR" pull --ff-only
else
    info "Cloning repository"
    git -C "$TOOLS_DIR" clone --depth 1 "$REPO_URL"
fi

# -----------------------------------------------------------------------------
# Create virtual environment
# -----------------------------------------------------------------------------

if [[ ! -d "$VENV_DIR" ]]; then
    info "Creating virtual environment"
    "$PYTHON_BIN" -m venv --system-site-packages "$VENV_DIR"
else
    info "Using existing virtual environment"
fi

# -----------------------------------------------------------------------------
# Install package or dependencies
# -----------------------------------------------------------------------------

info "Installing dependencies"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip setuptools wheel

if [[ -f "${REPO_DIR}/pyproject.toml" || -f "${REPO_DIR}/setup.py" ]]; then
    info "Detected installable Python package"
    python -m pip install "${REPO_DIR}"
elif [[ -f "${REPO_DIR}/requirements.txt" ]]; then
    info "Detected requirements.txt"
    python -m pip install -r "${REPO_DIR}/requirements.txt"
else
    warn "No pyproject.toml, setup.py, or requirements.txt found; skipping dependency installation"
fi

deactivate

# -----------------------------------------------------------------------------
# Locate executable
# -----------------------------------------------------------------------------

BIN_PATH=""

if [[ -x "${VENV_DIR}/bin/${ALIAS_NAME}" ]]; then
    BIN_PATH="${VENV_DIR}/bin/${ALIAS_NAME}"
elif [[ -f "${REPO_DIR}/${ALIAS_NAME}.py" ]]; then
    BIN_PATH="${VENV_DIR}/bin/python ${REPO_DIR}/${ALIAS_NAME}.py"
elif [[ -f "${REPO_DIR}/${REPO_NAME}.py" ]]; then
    BIN_PATH="${VENV_DIR}/bin/python ${REPO_DIR}/${REPO_NAME}.py"
else
    for candidate in \
        "${REPO_DIR}/main.py" \
        "${REPO_DIR}/run.py" \
        "${REPO_DIR}/cli.py" \
        "${REPO_DIR}/${ALIAS_NAME}.sh"
    do
        if [[ -f "$candidate" ]]; then
            if [[ "$candidate" == *.py ]]; then
                BIN_PATH="${VENV_DIR}/bin/python ${candidate}"
            else
                BIN_PATH="$candidate"
            fi
            break
        fi
    done
fi

if [[ -z "$BIN_PATH" ]]; then
    candidate="$(
        find "${VENV_DIR}/bin" -maxdepth 1 -type f -executable \
            ! -name 'python*' \
            ! -name 'pip*' \
            ! -name activate \
            | head -n 1
    )"

    if [[ -n "$candidate" ]]; then
        BIN_PATH="$candidate"
    fi
fi

[[ -n "$BIN_PATH" ]] || die "Unable to determine executable for ${REPO_NAME}."

# -----------------------------------------------------------------------------
# Add or update alias in shell configuration
# -----------------------------------------------------------------------------

ALIAS_LINE="alias ${ALIAS_NAME}=\"${BIN_PATH}\""

touch "$SHELL_RC"

if grep -qE "^alias ${ALIAS_NAME}=" "$SHELL_RC"; then
    info "Updating alias in ${SHELL_RC}"
    sed -i "s|^alias ${ALIAS_NAME}=.*|${ALIAS_LINE}|" "$SHELL_RC"
else
    info "Adding alias to ${SHELL_RC}"
    {
        echo
        echo "# Added by venver"
        echo "${ALIAS_LINE}"
    } >> "$SHELL_RC"
fi

# -----------------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------------

cat <<EOF

Installation summary
--------------------
Repository : ${REPO_DIR}
Virtualenv : ${VENV_DIR}
Executable : ${BIN_PATH}
Alias      : ${ALIAS_NAME}
Shell RC   : ${SHELL_RC}

To use the alias in the current shell:
  source ${SHELL_RC}

EOF
