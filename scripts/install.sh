#!/usr/bin/env bash
# ==============================================================================
# FlutterSDK AI — Universal Multi-Tool Installer
#
# Installs FlutterSDK AI skills, commands, and MCP server configuration
# into all detected AI coding tools.
#
# Usage:
#   bash install.sh --global              # Install for all tools (user-level)
#   bash install.sh --project             # Install into current project
#   bash install.sh --dry-run             # Preview what would be installed
#   bash install.sh --with-mcp            # Also inject mcp.fluttersdk.com config
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
VERSION="1.2.0"

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
WITH_MCP=false
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

# Merge JSON key into existing file using node (if available).
# Values flow through env vars (FILE/KEY/VALUE) so the node script never
# string-interpolates user input; safe under any callable value.
# When VALUE is a JSON array AND the target key already holds an array, the
# new entries are appended and deduplicated (preserves existing user entries
# in shared config files like opencode.json `skills.urls`).
merge_json_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} merge '${key}' into ${file}"
        return
    fi

    if command -v node &> /dev/null; then
        FILE="${file}" KEY="${key}" VALUE="${value}" node -e '
            const fs = require("fs");
            const path = process.env.FILE;
            let config = {};
            try { config = JSON.parse(fs.readFileSync(path, "utf8")); } catch {}
            const keys = process.env.KEY.split(".");
            const incoming = JSON.parse(process.env.VALUE);
            let obj = config;
            for (let i = 0; i < keys.length - 1; i++) {
                obj[keys[i]] = obj[keys[i]] || {};
                obj = obj[keys[i]];
            }
            const leaf = keys[keys.length - 1];
            const existing = obj[leaf];
            if (Array.isArray(incoming) && Array.isArray(existing)) {
                const merged = [...existing];
                for (const item of incoming) {
                    if (!merged.includes(item)) merged.push(item);
                }
                obj[leaf] = merged;
            } else {
                obj[leaf] = incoming;
            }
            fs.writeFileSync(path, JSON.stringify(config, null, 4) + "\n");
        '
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

    # 6. Codex CLI
    if command -v codex &> /dev/null; then
        INSTALLED_TOOLS+=("codex")
        success "Codex CLI detected"
    fi

    # 7. Antigravity CLI
    if command -v agy &> /dev/null; then
        INSTALLED_TOOLS+=("antigravity")
        success "Antigravity CLI detected"
    fi

    # 8. Cline (VS Code extension — no standalone binary)
    if [[ -d "$HOME/.vscode/extensions" ]] && find "$HOME/.vscode/extensions" -maxdepth 2 -name 'saoudrizwan.claude-dev-*' -print -quit 2>/dev/null | grep -q .; then
        INSTALLED_TOOLS+=("cline")
        success "Cline (VS Code extension) detected"
    fi

    # 9. Roo Code (VS Code extension — publisher prefix is 'roocode'; no standalone binary)
    if [[ -d "$HOME/.vscode/extensions" ]] && find "$HOME/.vscode/extensions" -maxdepth 2 -name 'roocode.*' -print -quit 2>/dev/null | grep -q .; then
        INSTALLED_TOOLS+=("roo")
        success "Roo Code (VS Code extension) detected"
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

    info "Claude Code plugins install via marketplace."
    info "From a Claude Code session, run:"
    info "  /plugin marketplace add https://raw.githubusercontent.com/fluttersdk/ai/main/.claude-plugin/marketplace.json"
    info "  /plugin install fluttersdk@fluttersdk-marketplace"
    info "The plugin auto-registers skills, commands, and the fluttersdk MCP (HTTP to mcp.fluttersdk.com)."
    success "Claude Code: Instructions printed"
}

install_global_cursor() {
    step "Configuring Cursor (global)..."

    local config_dir="${HOME}/.cursor/rules"

    ensure_dir "${config_dir}"
    copy_file "${REPO_ROOT}/tool-templates/cursor/fluttersdk.mdc" "${config_dir}/fluttersdk.mdc"

    success "Cursor: Installed fluttersdk.mdc rule"
}

install_global_gemini() {
    step "Configuring Gemini CLI (global)..."

    local config_dir="${HOME}/.gemini/commands"

    ensure_dir "${config_dir}"
    copy_file "${REPO_ROOT}/tool-templates/gemini/flutter-review.toml" "${config_dir}/flutter-review.toml"
    copy_file "${REPO_ROOT}/tool-templates/gemini/flutter-test.toml" "${config_dir}/flutter-test.toml"

    success "Gemini CLI: Installed command templates"
}

install_global_vscode() {
    step "Configuring VS Code Copilot (global)..."

    info "VS Code Copilot instructions are project-level."
    info "Use --project mode in your Flutter project directory."
    success "VS Code: Instructions printed"
}

install_global_codex() {
    step "Configuring Codex CLI (global)..."

    # Derive skill names dynamically so future registry additions need no install.sh edits.
    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest="${HOME}/.agents/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Codex: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Codex MCP config: add to ~/.codex/config.toml:"
    info "  [mcp_servers.fluttersdk]"
    info "  url = \"https://mcp.fluttersdk.com/\""
    info "  enabled = true"
    info "  (see docs/MCP.md for details)"
    success "Codex CLI: Skills installed (global)"
}

install_global_antigravity() {
    step "Configuring Antigravity CLI (global)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest="${HOME}/.gemini/antigravity-cli/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Antigravity: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    # Antigravity renamed the MCP field from httpUrl to serverUrl — do not use the legacy name.
    info "Antigravity MCP config: add to ~/.gemini/config/mcp_config.json:"
    info "  { \"mcpServers\": { \"fluttersdk\": { \"serverUrl\": \"https://mcp.fluttersdk.com/\" } } }"
    info "  Note: field is 'serverUrl' (NOT legacy 'httpUrl')"
    success "Antigravity CLI: Skills installed (global)"
}

install_global_cline() {
    step "Configuring Cline (global)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest="${HOME}/.cline/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Cline: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Cline MCP config: open Cline settings → MCP Servers → add server:"
    info "  Name: fluttersdk"
    info "  URL:  https://mcp.fluttersdk.com/"
    info "  (or edit cline_mcp_settings.json directly — see docs/MCP.md)"
    success "Cline: Skills installed (global)"
}

install_global_roo() {
    step "Configuring Roo Code (global)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    # Global storage path follows the Roo Code VS Code extension convention.
    # Defaulting to ~/.config/Roo-Code/GlobalStorage/skills/ as documented on
    # docs.roocode.com; adjust if the path changes in future Roo releases.
    while IFS= read -r skill_name; do
        local dest="${HOME}/.config/Roo-Code/GlobalStorage/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Roo Code: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Roo Code MCP config: add to ~/.config/Roo-Code/GlobalStorage/mcp_settings.json:"
    info "  { \"mcpServers\": { \"fluttersdk\": { \"url\": \"https://mcp.fluttersdk.com/\" } } }"
    success "Roo Code: Skills installed (global)"
}

# ==============================================================================
# MCP Config Injection (--with-mcp)
# ==============================================================================

# Inject mcp.fluttersdk.com config for a given tool.
# The server is public (throttle:60,1 only); no credentials required.
# $1 = tool name, $2 = mode (global|project)
install_mcp_for_tool() {
    local tool="$1"
    local mode="$2"

    case "${tool}" in
        claude)
            # Claude Code: print the command; do not auto-run it.
            info "Run: claude mcp add --transport http fluttersdk https://mcp.fluttersdk.com/"
            ;;

        cursor)
            if [[ "${mode}" == "global" ]]; then
                local config_file="${HOME}/.cursor/mcp.json"
            else
                local config_file=".cursor/mcp.json"
            fi
            ensure_dir "$(dirname "${config_file}")"
            merge_json_key "${config_file}" "mcpServers.fluttersdk" "{\"url\":\"https://mcp.fluttersdk.com/\"}"
            info "Cursor: https://mcp.fluttersdk.com/ added to ${config_file}"
            ;;

        opencode)
            if [[ "${mode}" == "global" ]]; then
                local config_file
                config_file="$(get_config_dir)/opencode/opencode.json"
            else
                local config_file="opencode.json"
            fi
            ensure_dir "$(dirname "${config_file}")"
            merge_json_key "${config_file}" "mcp.fluttersdk" "{\"type\":\"remote\",\"url\":\"https://mcp.fluttersdk.com/\"}"
            info "OpenCode: https://mcp.fluttersdk.com/ added to ${config_file}"
            ;;

        gemini)
            if [[ "${mode}" == "global" ]]; then
                local config_file="${HOME}/.gemini/settings.json"
            else
                local config_file=".gemini/settings.json"
            fi
            ensure_dir "$(dirname "${config_file}")"
            merge_json_key "${config_file}" "mcpServers.fluttersdk" "{\"url\":\"https://mcp.fluttersdk.com/\"}"
            info "Gemini CLI: https://mcp.fluttersdk.com/ added to ${config_file}"
            ;;

        antigravity)
            # Antigravity uses serverUrl (not url/httpUrl) per the breaking rename from Gemini CLI.
            # Config lives at the shared path regardless of global/project mode.
            local config_file="${HOME}/.gemini/config/mcp_config.json"
            ensure_dir "$(dirname "${config_file}")"
            merge_json_key "${config_file}" "mcpServers.fluttersdk" "{\"serverUrl\":\"https://mcp.fluttersdk.com/\"}"
            info "Antigravity: https://mcp.fluttersdk.com/ added to ${config_file}"
            ;;

        codex)
            # TOML merging is too complex for bash; print the copy-paste snippet instead.
            info "Codex CLI: Add to ~/.codex/config.toml:"
            cat <<'EOF'
[mcp_servers.fluttersdk]
url = "https://mcp.fluttersdk.com/"
enabled = true
EOF
            ;;

        vscode)
            # VS Code MCP config is project-level only.
            if [[ "${mode}" == "project" ]]; then
                local config_file=".vscode/mcp.json"
                ensure_dir ".vscode"
                merge_json_key "${config_file}" "servers.fluttersdk" "{\"type\":\"http\",\"url\":\"https://mcp.fluttersdk.com/\"}"
                info "VS Code: https://mcp.fluttersdk.com/ added to ${config_file}"
            else
                info "VS Code MCP config is project-level; re-run with --project --with-mcp to inject https://mcp.fluttersdk.com/."
            fi
            ;;

        cline)
            # Cline MCP settings are managed via the VS Code UI or cline_mcp_settings.json.
            # Print a copy-paste snippet because the exact file path varies by OS and Cline version.
            info "Cline: Add to your Cline MCP settings (via UI or cline_mcp_settings.json):"
            cat <<'EOF'
{
    "mcpServers": {
        "fluttersdk": {
            "url": "https://mcp.fluttersdk.com/"
        }
    }
}
EOF
            ;;

        roo)
            if [[ "${mode}" == "project" ]]; then
                local config_file=".roo/mcp.json"
                ensure_dir ".roo"
                merge_json_key "${config_file}" "mcpServers.fluttersdk" "{\"url\":\"https://mcp.fluttersdk.com/\"}"
                info "Roo Code: https://mcp.fluttersdk.com/ added to ${config_file}"
            else
                local config_file="${HOME}/.config/Roo-Code/GlobalStorage/mcp_settings.json"
                ensure_dir "$(dirname "${config_file}")"
                merge_json_key "${config_file}" "mcpServers.fluttersdk" "{\"url\":\"https://mcp.fluttersdk.com/\"}"
                info "Roo Code: https://mcp.fluttersdk.com/ added to ${config_file}"
            fi
            ;;
    esac
}

install_global() {
    info "Installing FlutterSDK AI globally (user-level)..."
    echo ""

    detect_tools

    for tool in "${INSTALLED_TOOLS[@]}"; do
        echo ""
        case "${tool}" in
            opencode)    install_global_opencode ;;
            claude)      install_global_claude ;;
            cursor)      install_global_cursor ;;
            gemini)      install_global_gemini ;;
            vscode)      install_global_vscode ;;
            codex)       install_global_codex ;;
            antigravity) install_global_antigravity ;;
            cline)       install_global_cline ;;
            roo)         install_global_roo ;;
        esac
    done

    if [[ "${WITH_MCP}" == true ]]; then
        echo ""
        step "Injecting MCP config for detected tools (--with-mcp)..."
        for tool in "${INSTALLED_TOOLS[@]}"; do
            install_mcp_for_tool "${tool}" "global"
        done
    fi

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
    copy_file "${REPO_ROOT}/commands/flutter-review.md" "${commands_dir}/flutter-review.md"
    copy_file "${REPO_ROOT}/commands/flutter-test.md" "${commands_dir}/flutter-test.md"

    success "Claude Code: Installed command templates"
}

install_project_cursor() {
    step "Configuring Cursor (project)..."

    local rules_dir=".cursor/rules"

    ensure_dir "${rules_dir}"
    copy_file "${REPO_ROOT}/tool-templates/cursor/fluttersdk.mdc" "${rules_dir}/fluttersdk.mdc"

    success "Cursor: Installed fluttersdk.mdc rule"
}

install_project_gemini() {
    step "Configuring Gemini CLI (project)..."

    local commands_dir=".gemini/commands"

    ensure_dir "${commands_dir}"
    copy_file "${REPO_ROOT}/tool-templates/gemini/flutter-review.toml" "${commands_dir}/flutter-review.toml"
    copy_file "${REPO_ROOT}/tool-templates/gemini/flutter-test.toml" "${commands_dir}/flutter-test.toml"

    success "Gemini CLI: Installed command templates"
}

install_project_vscode() {
    step "Configuring VS Code Copilot (project)..."

    local github_dir=".github"

    ensure_dir "${github_dir}"
    copy_file "${REPO_ROOT}/.github/copilot-instructions.md" "${github_dir}/copilot-instructions.md"

    success "VS Code: Installed copilot-instructions.md"
}

install_project_codex() {
    step "Configuring Codex CLI (project)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest=".agents/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Codex: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Codex MCP config: add to ~/.codex/config.toml:"
    info "  [mcp_servers.fluttersdk]"
    info "  url = \"https://mcp.fluttersdk.com/\""
    info "  enabled = true"
    info "  (see docs/MCP.md for details)"
    success "Codex CLI: Skills installed (project)"
}

install_project_antigravity() {
    step "Configuring Antigravity CLI (project)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    # Antigravity reads workspace skills from .agents/skills/ (same path as Codex workspace).
    while IFS= read -r skill_name; do
        local dest=".agents/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Antigravity: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Antigravity MCP config: add to ~/.gemini/config/mcp_config.json:"
    info "  { \"mcpServers\": { \"fluttersdk\": { \"serverUrl\": \"https://mcp.fluttersdk.com/\" } } }"
    info "  Note: field is 'serverUrl' (NOT legacy 'httpUrl')"
    success "Antigravity CLI: Skills installed (project)"
}

install_project_cline() {
    step "Configuring Cline (project)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest=".cline/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Cline: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Cline MCP config: open Cline settings → MCP Servers → add server:"
    info "  Name: fluttersdk"
    info "  URL:  https://mcp.fluttersdk.com/"
    info "  (or edit cline_mcp_settings.json directly — see docs/MCP.md)"
    success "Cline: Skills installed (project)"
}

install_project_roo() {
    step "Configuring Roo Code (project)..."

    local skills_index="${REPO_ROOT}/skills/index.json"
    while IFS= read -r skill_name; do
        local dest=".roo/skills/${skill_name}"
        ensure_dir "${dest}"
        if [[ "${DRY_RUN}" == false ]]; then
            cp -R "${REPO_ROOT}/skills/${skill_name}/." "${dest}/"
        else
            echo -e "  ${YELLOW}[DRY-RUN]${NC} cp -R ${REPO_ROOT}/skills/${skill_name}/ → ${dest}/"
        fi
        success "Roo Code: Installed skill '${skill_name}' to ${dest}"
    done < <(jq -r '.skills[].name' "${skills_index}")

    info "Roo Code MCP config: add to .roo/mcp.json:"
    info "  { \"mcpServers\": { \"fluttersdk\": { \"url\": \"https://mcp.fluttersdk.com/\" } } }"
    success "Roo Code: Skills installed (project)"
}

install_project() {
    info "Installing FlutterSDK AI into current project..."
    info "Target: $(pwd)"
    echo ""

    detect_tools

    for tool in "${INSTALLED_TOOLS[@]}"; do
        echo ""
        case "${tool}" in
            opencode)    install_project_opencode ;;
            claude)      install_project_claude ;;
            cursor)      install_project_cursor ;;
            gemini)      install_project_gemini ;;
            vscode)      install_project_vscode ;;
            codex)       install_project_codex ;;
            antigravity) install_project_antigravity ;;
            cline)       install_project_cline ;;
            roo)         install_project_roo ;;
        esac
    done

    if [[ "${WITH_MCP}" == true ]]; then
        echo ""
        step "Injecting MCP config for detected tools (--with-mcp)..."
        for tool in "${INSTALLED_TOOLS[@]}"; do
            install_mcp_for_tool "${tool}" "project"
        done
    fi

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
    --with-mcp    Also inject mcp.fluttersdk.com config for every detected tool
    --help        Show this help message

Examples:
    bash install.sh --global                        # Configure all detected AI tools
    bash install.sh --project                       # Add configs to current Flutter project
    bash install.sh --dry-run --global              # Preview global installation
    bash install.sh --dry-run --project             # Preview project installation
    bash install.sh --global --with-mcp             # Install + inject MCP config
    bash install.sh --dry-run --global --with-mcp   # Preview MCP config injection

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
            --with-mcp)
                WITH_MCP=true
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
