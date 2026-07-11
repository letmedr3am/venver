#!/usr/bin/env bash
#
# venver
#
# Clone a Python-based Git repository (or use a local directory), create an
# isolated virtual environment, install dependencies, and add/update an alias
# in ~/.zshrc.
#
# Supported repository layouts:
#   1. pyproject.toml or setup.py  -> python -m pip install <repo>
#   2. requirements.txt only      -> python -m pip install -r requirements.txt
#   3. Standalone *.py scripts    -> alias runs the script with the venv Python
#
# Usage:
#   ./venver [options] <git-repository-url>
#   ./venver [options] --local <local-directory>
#
# Options (all optional):
#   --local PATH        Use a local directory instead of cloning a repository
#   --tools-dir DIR     Repository root directory (default: /opt/tools)
#   --python-bin BIN    Python interpreter (default: python3.13)
#   --shell-rc FILE     Shell rc file to update (default: ~/.zshrc)
#   --alias NAME        Alias name (default: lowercase repository/directory name)
#   -h, --help          Show this help
#
# Examples:
#   ./venver https://github.com/ly4k/Certipy
#   ./venver https://github.com/AutoRecon/AutoRecon
#   ./venver --python-bin python3.12 \
#       https://github.com/fortra/impacket
#   ./venver --tools-dir ~/tools --alias certipy-ad \
#       https://github.com/ly4k/Certipy
#   ./venver --local ~/projects/mytool
#   ./venver --local /opt/src/mytool --alias mytool

set -euo pipefail

# -----------------------------------------------------------------------------
# Default configuration
# -----------------------------------------------------------------------------

TOOLS_DIR="/opt/tools"
PYTHON_BIN=""
SHELL_RC="${HOME}/.zshrc"
ALIAS_NAME=""
REPO_URL=""
LOCAL_DIR=""
EXTRAS=""

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
# Python interpreter detection
# -----------------------------------------------------------------------------
# Scans PATH for python3.X binaries and returns the highest version found.
# Falls back to a bare "python3" if no versioned interpreter is present.
# Used only when --python-bin was not explicitly provided.

detect_python_bin() {
    local dir bin name version
    local -A seen=()
    local best_name="" best_version=-1

    local old_ifs="$IFS"
    IFS=':'
    local path_dirs=($PATH)
    IFS="$old_ifs"

    for dir in "${path_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        for bin in "$dir"/python3.*; do
            [[ -f "$bin" && -x "$bin" ]] || continue
            name="$(basename "$bin")"
            [[ "$name" =~ ^python3\.([0-9]+)$ ]] || continue
            [[ -n "${seen[$name]:-}" ]] && continue
            seen["$name"]=1
            version="${BASH_REMATCH[1]}"
            if (( version > best_version )); then
                best_version="$version"
                best_name="$name"
            fi
        done
    done

    if [[ -n "$best_name" ]]; then
        echo "$best_name"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options] <git-repository-url>
       ${SCRIPT_NAME} [options] --local <local-directory>

Clone a Python-based Git repository (or use a local directory), create an
isolated virtual environment, install dependencies, and add/update an alias
in your shell configuration.

Options (all optional):
  --local PATH        Use a local directory instead of cloning a repository
  --tools-dir DIR     Repository root directory (default: ${TOOLS_DIR})
                      (ignored when --local is used; the venv is created
                       inside the local directory itself)
  --python-bin BIN    Python interpreter (default: newest python3.x found in PATH)
  --shell-rc FILE     Shell rc file to update (default: ${SHELL_RC})
  --alias NAME        Alias name (default: lowercase repository/directory name)
  --extras NAME       Install optional-dependencies group (e.g. "dev", "all")
                      when the repo is an installable package
  -h, --help          Show this help

Examples:
  ${SCRIPT_NAME} https://github.com/ly4k/Certipy
  ${SCRIPT_NAME} https://github.com/AutoRecon/AutoRecon
  ${SCRIPT_NAME} --python-bin python3.12 \\
      https://github.com/fortra/impacket
  ${SCRIPT_NAME} --tools-dir ~/tools --alias certipy-ad \\
      https://github.com/ly4k/Certipy
  ${SCRIPT_NAME} --local ~/projects/mytool
  ${SCRIPT_NAME} --local /opt/src/mytool --alias mytool
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
        --local)
            [[ $# -ge 2 ]] || die "Missing value for --local"
            LOCAL_DIR="$2"
            shift 2
            ;;
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
        --extras)
            [[ $# -ge 2 ]] || die "Missing value for --extras"
            EXTRAS="$2"
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

# Validate: exactly one source must be provided
if [[ -n "$LOCAL_DIR" && -n "$REPO_URL" ]]; then
    die "Cannot use --local together with a repository URL. Specify one or the other."
fi

if [[ -z "$LOCAL_DIR" && -z "$REPO_URL" ]]; then
    usage >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Expand paths
# -----------------------------------------------------------------------------

TOOLS_DIR="${TOOLS_DIR/#\~/$HOME}"
SHELL_RC="${SHELL_RC/#\~/$HOME}"
LOCAL_DIR="${LOCAL_DIR/#\~/$HOME}"

# -----------------------------------------------------------------------------
# Derived values
# -----------------------------------------------------------------------------

if [[ -n "$LOCAL_DIR" ]]; then
    # Resolve to an absolute path and strip any trailing slash
    LOCAL_DIR="$(realpath -m "$LOCAL_DIR")"
    REPO_NAME="$(basename "$LOCAL_DIR")"
    REPO_DIR="$LOCAL_DIR"
else
    REPO_NAME="$(basename -s .git "$REPO_URL")"
    REPO_DIR="${TOOLS_DIR}/${REPO_NAME}"
fi

VENV_DIR="${REPO_DIR}/venv"

if [[ -z "$ALIAS_NAME" ]]; then
    ALIAS_NAME="$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')"
fi

# -----------------------------------------------------------------------------
# Validate prerequisites
# -----------------------------------------------------------------------------

command -v git >/dev/null 2>&1 || die "git is not installed."

if [[ -z "$PYTHON_BIN" ]]; then
    info "No --python-bin specified; searching PATH for a Python interpreter"
    if ! PYTHON_BIN="$(detect_python_bin)"; then
        die "No Python 3 interpreter found in PATH. Install one or specify --python-bin."
    fi
    info "Using detected interpreter: ${PYTHON_BIN}"
fi

command -v "$PYTHON_BIN" >/dev/null 2>&1 || die "Python interpreter not found: ${PYTHON_BIN}"

# -----------------------------------------------------------------------------
# Configuration summary
# -----------------------------------------------------------------------------

if [[ -n "$LOCAL_DIR" ]]; then
    info "Source         : local directory"
    info "Local dir      : ${LOCAL_DIR}"
else
    info "Source         : git repository"
    info "Repository URL : ${REPO_URL}"
fi
info "Repository     : ${REPO_NAME}"
[[ -z "$LOCAL_DIR" ]] && info "Tools dir      : ${TOOLS_DIR}"
info "Python bin     : ${PYTHON_BIN}"
info "Shell RC       : ${SHELL_RC}"
info "Alias          : ${ALIAS_NAME}"
[[ -n "$EXTRAS" ]] && info "Extras         : ${EXTRAS}"

# -----------------------------------------------------------------------------
# Source acquisition: clone/update OR validate local directory
# -----------------------------------------------------------------------------

if [[ -n "$LOCAL_DIR" ]]; then
    # --- Local mode ---
    [[ -d "$LOCAL_DIR" ]] || die "Local directory does not exist: ${LOCAL_DIR}"
    [[ -r "$LOCAL_DIR" ]] || die "Local directory is not readable: ${LOCAL_DIR}"
    info "Using local directory: ${LOCAL_DIR}"
else
    # --- Git mode ---
    info "Ensuring tools directory exists"
    sudo mkdir -p "$TOOLS_DIR"
    sudo chown -R "$USER:$USER" "$TOOLS_DIR"

    if [[ -d "${REPO_DIR}/.git" ]]; then
        info "Updating repository"
        git -C "$REPO_DIR" pull --ff-only
    else
        info "Cloning repository"
        git -C "$TOOLS_DIR" clone --depth 1 "$REPO_URL"
    fi
fi

# -----------------------------------------------------------------------------
# Create virtual environment
# -----------------------------------------------------------------------------

if [[ ! -d "$VENV_DIR" ]]; then
    info "Creating virtual environment"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
elif grep -qE '^include-system-site-packages\s*=\s*true' "${VENV_DIR}/pyvenv.cfg" 2>/dev/null; then
    warn "Existing venv includes system site-packages (not fully isolated); rebuilding"
    rm -rf "$VENV_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
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

    INSTALL_TARGET="${REPO_DIR}"
    if [[ -n "$EXTRAS" ]]; then
        INSTALL_TARGET="${REPO_DIR}[${EXTRAS}]"
        info "Requested extras group: ${EXTRAS}"
    fi

    # Prefer an editable install (matches `pip install -e .` behavior, including
    # any build-time deps or custom develop/editable hooks the backend defines).
    # Not every backend implements PEP 660 (build_editable), so fall back to a
    # regular install if the editable attempt fails.
    info "Attempting editable install"
    if python -m pip install -e "$INSTALL_TARGET"; then
        info "Editable install succeeded"
    else
        warn "Editable install failed; falling back to regular install"
        python -m pip install "$INSTALL_TARGET"
    fi
elif [[ -f "${REPO_DIR}/requirements.txt" ]]; then
    info "Detected requirements.txt"
    [[ -n "$EXTRAS" ]] && warn "--extras ignored: no installable package (pyproject.toml/setup.py) found"
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

# -----------------------------------------------------------------------------
# Optional: add further aliases interactively
# -----------------------------------------------------------------------------
# Placed at the very end, after everything has installed successfully, so the
# user is never asked to enter data for a run that's about to fail.

if [[ -t 0 ]]; then
    read -rp "Add extra alias name(s) for '${ALIAS_NAME}' (comma-separated, blank to skip): " extra_input || extra_input=""

    if [[ -n "$extra_input" ]]; then
        IFS=',' read -ra extra_names <<< "$extra_input"

        for raw_name in "${extra_names[@]}"; do
            # trim leading/trailing whitespace
            extra_name="$(echo "$raw_name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

            [[ -z "$extra_name" ]] && continue

            if ! [[ "$extra_name" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]; then
                warn "Invalid alias name '${extra_name}'; use letters, digits, '_' or '-'. Skipping."
                continue
            fi

            extra_line="alias ${extra_name}=\"${BIN_PATH}\""

            if grep -qE "^alias ${extra_name}=" "$SHELL_RC"; then
                info "Updating alias '${extra_name}' in ${SHELL_RC}"
                sed -i "s|^alias ${extra_name}=.*|${extra_line}|" "$SHELL_RC"
            else
                info "Adding alias '${extra_name}' to ${SHELL_RC}"
                {
                    echo
                    echo "# Added by venver (extra alias for ${ALIAS_NAME})"
                    echo "${extra_line}"
                } >> "$SHELL_RC"
            fi
        done
    fi
else
    info "Non-interactive shell detected; skipping extra alias prompt."
fi
