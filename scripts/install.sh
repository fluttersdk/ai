#!/usr/bin/env bash
# ==============================================================================
# FlutterSDK AI — Universal Multi-Tool Installer
#
# Installs FlutterSDK AI skills, commands, and MCP server configuration
# into all detected AI coding tools.
#
# Usage:
#   bash install.sh --global     # Install for all tools (user-level)
#   bash install.sh --project    # Install into current project
#   bash install.sh --dry-run    # Preview what would be installed
#
# Author: Anilcan Cakir <anilcan.cakir@gmail.com>
# License: MIT
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Constants
# ==============================================================================

REPO_URL="https://github.com/fluttersdk/ai"
REGISTRY_URL="https://fluttersdk.github.io/ai/"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No color

# ==============================================================================
# State
# ==============================================================================

DRY_RUN=false
MODE=""
INSTALLED_TOOLS=()

# ==============================================================================
# Helpers
# ==============================================================================

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
step()    { echo -e "${CYAN}→${NC} $1"; }

# Resolve XDG config directory with platform-aware fallback.
get_config_dir() {
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        echo "${XDG_CONFIG_HOME}"
    elif [[ "$(uname)" == "Darwin" ]]; then
        echo "${HOME}/.config"
    else
        echo "${HOME}/.config"
    fi
}

# Create directory (or print what would be created in dry-run mode).
ensure_dir() {
    local dir="$1"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} mkdir -p ${dir}"
        return
    fi

    mkdir -p "${dir}"
}

# Copy file (or print what would be copied in dry-run mode).
copy_file() {
    local src="$1"
    local dst="$2"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} cp ${src} → ${dst}"
        return
    fi

    cp "${src}" "${dst}"
}

# Write content to file (or print in dry-run mode).
write_file() {
    local dst="$1"
    local content="$2"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} write ${dst}"
        return
    fi

    echo "${content}" > "${dst}"
}

# Merge JSON key into existing file using node (if available) or simple append.
merge_json_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} merge '${key}' into ${file}"
        return
    fi

    if command -v node &> /dev/null; then
        node -e "
            const fs = require('fs');
            const path = '${file}';
            let config = {};
            try { config = JSON.parse(fs.readFileSync(path, 'utf8')); } catch {}
            const keys = '${key}'.split('.');
            let obj = config;
            for (let i = 0; i < keys.length - 1; i++) {
                obj[keys[i]] = obj[keys[i]] || {};
                obj = obj[keys[i]];
            }
            obj[keys[keys.length - 1]] = JSON.parse('${value}');
            fs.writeFileSync(path, JSON.stringify(config, null, 4) + '\n');
        "
    else
        warn "Node.js not found — cannot merge JSON. Please add manually."
    fi
}

# ==============================================================================
# Tool Detection
# ==============================================================================

detect_tools() {
    info "Detecting installed AI coding tools..."

    # 1. OpenCode
    if command -v opencode &> /dev/null; then
        INSTALLED_TOOLS+=("opencode")
        success "OpenCode detected"
    fi

    # 2. Claude Code
    if command -v claude &> /dev/null; then
        INSTALLED_TOOLS+=("claude")
        success "Claude Code detected"
    fi

    # 3. Cursor (check for config directory)
    if [[ -d "${HOME}/.cursor" ]] || [[ -d "${HOME}/Library/Application Support/Cursor" ]]; then
        INSTALLED_TOOLS+=("cursor")
        success "Cursor detected"
    fi

    # 4. Gemini CLI
    if command -v gemini &> /dev/null; then
        INSTALLED_TOOLS+=("gemini")
        success "Gemini CLI detected"
    fi

    # 5. VS Code with Copilot
    if command -v code &> /dev/null; then
        INSTALLED_TOOLS+=("vscode")
        success "VS Code detected"
    fi

    if [[ ${#INSTALLED_TOOLS[@]} -eq 0 ]]; then
        warn "No AI coding tools detected. Install will configure files anyway."
    else
        info "Found ${#INSTALLED_TOOLS[@]} tool(s): ${INSTALLED_TOOLS[*]}"
    fi
}

# ==============================================================================
# Global Install (User-Level Configuration)
# ==============================================================================

install_global_opencode() {
    step "Configuring OpenCode (global)..."

    local config_dir
    config_dir="$(get_config_dir)/opencode"
    local config_file="${config_dir}/opencode.json"

    ensure_dir "${config_dir}"

    # Add registry URL to skills.urls
    merge_json_key "${config_file}" "skills.urls" "[\"${REGISTRY_URL}\"]"

    success "OpenCode: Added ${REGISTRY_URL} to skills.urls"
}

install_global_claude() {
    step "Configuring Claude Code (global)..."

    info "Claude Code plugins are installed per-project or via marketplace."
    info "Run: claude plugin install --from ${REPO_URL}"
    info "  or: /plugin marketplace add fluttersdk/ai"
    success "Claude Code: Instructions printed"
}

install_global_cursor() {
    step "Configuring Cursor (global)..."

    local config_dir="${HOME}/.cursor/rules"

    ensure_dir "${config_dir}"
    copy_file "${REPO_ROOT}/commands/cursor/fluttersdk.mdc" "${config_dir}/fluttersdk.mdc"

    success "Cursor: Installed fluttersdk.mdc rule"
}

install_global_gemini() {
    step "Configuring Gemini CLI (global)..."

    local config_dir="${HOME}/.gemini/commands"

    ensure_dir "${config_dir}"
    copy_file "${REPO_ROOT}/commands/gemini/flutter-review.toml" "${config_dir}/flutter-review.toml"
    copy_file "${REPO_ROOT}/commands/gemini/flutter-test.toml" "${config_dir}/flutter-test.toml"

    success "Gemini CLI: Installed command templates"
}

install_global_vscode() {
    step "Configuring VS Code Copilot (global)..."

    info "VS Code Copilot instructions are project-level."
    info "Use --project mode in your Flutter project directory."
    success "VS Code: Instructions printed"
}

install_global() {
    info "Installing FlutterSDK AI globally (user-level)..."
    echo ""

    detect_tools

    for tool in "${INSTALLED_TOOLS[@]}"; do
        echo ""
        case "${tool}" in
            opencode) install_global_opencode ;;
            claude)   install_global_claude ;;
            cursor)   install_global_cursor ;;
            gemini)   install_global_gemini ;;
            vscode)   install_global_vscode ;;
        esac
    done

    echo ""
    success "Global installation complete!"
}

# ==============================================================================
# Project Install (Current Directory)
# ==============================================================================

install_project_opencode() {
    step "Configuring OpenCode (project)..."

    local config_file="opencode.json"

    # Add registry URL to project-level opencode.json
    merge_json_key "${config_file}" "skills.urls" "[\"${REGISTRY_URL}\"]"

    success "OpenCode: Added registry URL to project opencode.json"
}

install_project_claude() {
    step "Configuring Claude Code (project)..."

    local commands_dir=".claude/commands"

    ensure_dir "${commands_dir}"
    copy_file "${REPO_ROOT}/commands/claude/flutter-review.md" "${commands_dir}/flutter-review.md"
    copy_file "${REPO_ROOT}/commands/claude/flutter-test.md" "${commands_dir}/flutter-test.md"

    success "Claude Code: Installed command templates"
}

install_project_cursor() {
    step "Configuring Cursor (project)..."

    local rules_dir=".cursor/rules"

    ensure_dir "${rules_dir}"
    copy_file "${REPO_ROOT}/commands/cursor/fluttersdk.mdc" "${rules_dir}/fluttersdk.mdc"

    success "Cursor: Installed fluttersdk.mdc rule"
}

install_project_gemini() {
    step "Configuring Gemini CLI (project)..."

    local commands_dir=".gemini/commands"

    ensure_dir "${commands_dir}"
    copy_file "${REPO_ROOT}/commands/gemini/flutter-review.toml" "${commands_dir}/flutter-review.toml"
    copy_file "${REPO_ROOT}/commands/gemini/flutter-test.toml" "${commands_dir}/flutter-test.toml"

    success "Gemini CLI: Installed command templates"
}

install_project_vscode() {
    step "Configuring VS Code Copilot (project)..."

    local github_dir=".github"

    ensure_dir "${github_dir}"
    copy_file "${REPO_ROOT}/.github/copilot-instructions.md" "${github_dir}/copilot-instructions.md"

    success "VS Code: Installed copilot-instructions.md"
}

install_project() {
    info "Installing FlutterSDK AI into current project..."
    info "Target: $(pwd)"
    echo ""

    detect_tools

    for tool in "${INSTALLED_TOOLS[@]}"; do
        echo ""
        case "${tool}" in
            opencode) install_project_opencode ;;
            claude)   install_project_claude ;;
            cursor)   install_project_cursor ;;
            gemini)   install_project_gemini ;;
            vscode)   install_project_vscode ;;
        esac
    done

    echo ""
    success "Project installation complete!"
}

# ==============================================================================
# CLI Entry Point
# ==============================================================================

usage() {
    cat <<EOF
FlutterSDK AI Installer v${VERSION}

Usage:
    bash install.sh [OPTIONS]

Options:
    --global      Install globally (user-level config for all tools)
    --project     Install into current project directory
    --dry-run     Preview changes without writing anything
    --help        Show this help message

Examples:
    bash install.sh --global              # Configure all detected AI tools
    bash install.sh --project             # Add configs to current Flutter project
    bash install.sh --dry-run --global    # Preview global installation
    bash install.sh --dry-run --project   # Preview project installation

Repository: ${REPO_URL}
Registry:   ${REGISTRY_URL}
EOF
}

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   FlutterSDK AI Installer v${VERSION}        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --global)
                MODE="global"
                shift
                ;;
            --project)
                MODE="project"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                warn "Dry-run mode enabled — no files will be modified."
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate mode
    if [[ -z "${MODE}" ]]; then
        error "Please specify --global or --project."
        echo ""
        usage
        exit 1
    fi

    # Execute
    case "${MODE}" in
        global)  install_global ;;
        project) install_project ;;
    esac

    echo ""
    info "Documentation: ${REPO_URL}"
    info "Report issues: ${REPO_URL}/issues"
    echo ""
}

main "$@"
