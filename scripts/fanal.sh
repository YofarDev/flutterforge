#!/usr/bin/env bash
# ============================================================
# flutter_preanalysis.sh  (fanal)
# Compact pre-analysis of a Flutter project for LLM audit.
#
# Usage:
#   ./flutter_preanalysis.sh [path/to/flutter/project]
#   ./flutter_preanalysis.sh          # defaults to current dir
#
# Output:
#   flutter_analysis_<timestamp>.md   # written next to this script
# ============================================================

set -euo pipefail

PROJECT_DIR="${1:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
LIB_DIR="$PROJECT_DIR/lib"
FEATURES_DIR="$LIB_DIR/features"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT_FILE="$(pwd)/flutter_analysis_${TIMESTAMP}.md"

# ── Helpers ────────────────────────────────────────────────
h2()  { echo ""; echo "## $*"; }
info(){ echo "$*"; }

dart_files() {
  find "$LIB_DIR" -name "*.dart" \
    ! -name "*.g.dart" \
    ! -name "*.freezed.dart" \
    2>/dev/null
}

lines_in_file() { wc -l < "$1" | tr -d ' '; }

# ── Start writing report ────────────────────────────────────
{

info "# Flutter Pre-Analysis — $(date +%Y-%m-%d)"
info "_Project: \`$PROJECT_DIR\`_"

# ── 0. File tree ────────────────────────────────────────────
h2 "File tree"

if [[ -d "$FEATURES_DIR" ]]; then
  FEAT_NAMES=$(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d \
    | sort | xargs -I{} basename {} | tr '\n' ' ' | sed 's/ $//')
  info "_Features: ${FEAT_NAMES}_"
  info ""
fi

info '```'
NODE=0
while IFS= read -r f; do
  rel="${f#${LIB_DIR}/}"
  slashes=$(echo "$rel" | tr -cd '/' | wc -c)
  rel_depth=$(( slashes > 0 ? slashes - 1 : 0 ))
  indent=""
  for (( i=0; i<rel_depth; i++ )); do indent+="│   "; done
  base=$(basename "$f")

  lc=$(wc -l < "$f" | tr -d ' ')
  limit=300
  echo "$base" | grep -qiE '(service|repository|repo|api)' && limit=400
  flag=""
  [[ "$lc" -gt "$limit" ]] && flag=" (!)"

  NODE=$((NODE + 1))
  printf '%s+-- [%d] %s  (%d lines)%s\n' "$indent" "$NODE" "$base" "$lc" "$flag"
done < <(
  find "$LIB_DIR" -type f -name "*.dart" \
    ! -name "*.g.dart" \
    ! -name "*.freezed.dart" \
    ! -name ".gitkeep" \
    | sort
)
info '```'

# ── 1. Feature map ──────────────────────────────────────────
h2 "Feature map"
if [[ -d "$FEATURES_DIR" ]]; then
  while IFS= read -r feat; do
    name=$(basename "$feat")
    layers=""
    [[ -d "$feat/data" ]]         && layers+="data "
    [[ -d "$feat/domain" ]]       && layers+="domain "
    [[ -d "$feat/presentation" ]] && layers+="presentation"
    info "- **$name**: ${layers:-⚠️ no standard layers}"
  done < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
else
  info "❌ No \`lib/features/\` directory found"
fi

# ── 2. Core layout ──────────────────────────────────────────
h2 "Core layout"
CORE_DIR="$LIB_DIR/core"
if [[ -d "$CORE_DIR" ]]; then
  for sub in agent audio avatar di llm router models services utils widgets; do
    if [[ -d "$CORE_DIR/$sub" ]]; then
      echo "✅ core/$sub"
    else
      # Distinguish expected new dirs from original ones
      case "$sub" in
        agent|audio|avatar|llm) echo "⚠️  core/$sub (missing — recommended for solid agent architecture)" ;;
        *) echo "❌ core/$sub" ;;
      esac
    fi
  done
else
  info "❌ No \`lib/core/\` directory found"
fi

# ── 3. File size violations ─────────────────────────────────
h2 "File size violations"
info "_Limits: general ≤300 · service/repo/api ≤400_"
FOUND=0
while IFS= read -r f; do
  lc=$(lines_in_file "$f")
  limit=300
  base=$(basename "$f")
  echo "$base" | grep -qiE '(service|repository|repo|api)' && limit=400
  if [[ "$lc" -gt "$limit" ]]; then
    info "- \`${f#$PROJECT_DIR/}\` — $lc lines (limit $limit)"
    FOUND=1
  fi
done < <(dart_files)
[[ "$FOUND" -eq 0 ]] && info "✅ None"

# ── 4. Cross-feature imports ────────────────────────────────
h2 "Cross-feature imports"
if [[ -d "$FEATURES_DIR" ]]; then
  FOUND=0
  while IFS= read -r f; do
    current=$(echo "$f" | sed "s|$FEATURES_DIR/||" | cut -d'/' -f1)
    while IFS= read -r line; do
      imported=$(echo "$line" | grep -oE "features/[^/'\"]+" || true)
      if [[ -n "$imported" ]]; then
        target=$(echo "$imported" | cut -d'/' -f2)
        if [[ -n "$target" && "$target" != "$current" ]]; then
          [[ "$FOUND" -eq 0 ]] && info ""
          info "- \`${f#$PROJECT_DIR/}\`: **$current** → **$target**"
          info "  \`$line\`"
          FOUND=1
        fi
      fi
    done < <(grep -n "^import" "$f" 2>/dev/null || true)
  done < <(dart_files | grep -F "$FEATURES_DIR" || true)
  [[ "$FOUND" -eq 0 ]] && info "✅ None"
else
  info "⚠️ No features/ dir — skipped"
fi

# ── 5. Anti-pattern scan ────────────────────────────────────
h2 "Anti-pattern scan"

scan_files() {
  local label="$1" pattern="$2" exclude="${3:-__none__}"
  local hits
  hits=$(dart_files | xargs grep -l "$pattern" 2>/dev/null \
    | grep -v "$exclude" || true)
  if [[ -n "$hits" ]]; then
    info ""
    info "**$label**"
    while IFS= read -r f; do
      info "- \`${f#$PROJECT_DIR/}\`"
    done <<< "$hits"
  fi
}

scan_lines() {
  local label="$1" pattern="$2" cap="${3:-3}"
  local found=0
  while IFS= read -r f; do
    matches=$(grep -n "$pattern" "$f" 2>/dev/null | head -"$cap" || true)
    if [[ -n "$matches" ]]; then
      [[ "$found" -eq 0 ]] && { info ""; info "**$label**"; found=1; }
      rel="${f#$PROJECT_DIR/}"
      while IFS= read -r line; do
        info "- \`$rel:$line\`"
      done <<< "$matches"
    fi
  done < <(dart_files)
}

scan_files  "Hardcoded colors (use colorScheme)"          "Colors\.\|Color(0x"
scan_files  "print / debugPrint (use AppLogger)"           "print(\|debugPrint(" "logger.dart"
scan_lines  "Navigation in build() (use BlocListener)"    "context\.go(\|GoRouter\.of(context)\.go" 3
scan_lines  "Widget helper methods (extract to class)"     "Widget _build" 3
scan_lines  "Nested BlocListeners (use MultiBlocListener)" "child:.*BlocListener\b" 3

# ── 6. DI wiring integrity ──────────────────────────────────
h2 "DI wiring integrity"

SL_FILE=$(dart_files | grep -E 'service_locator\.dart|injection\.dart' | head -1 || true)
if [[ -n "$SL_FILE" ]]; then
  rel="${SL_FILE#$PROJECT_DIR/}"
  REG_COUNT=$(grep -c "registerLazy\|registerFactory\|registerSingleton" "$SL_FILE" 2>/dev/null || echo 0)
  info "✅ \`$rel\` — $REG_COUNT registration(s)"

  # Dual wiring: cubits constructed manually outside service_locator
  DUAL_WIRING=$(dart_files | grep -v "$(basename "$SL_FILE")" \
    | xargs grep -ln "Cubit(\|Bloc(" 2>/dev/null \
    | grep -v "_test\.dart\|_cubit\.dart\|_bloc\.dart\|_state\.dart" || true)
  if [[ -n "$DUAL_WIRING" ]]; then
    info ""
    info "⚠️  **Dual wiring — cubits constructed outside service_locator** (should use getIt only):"
    while IFS= read -r f; do
      info "  - \`${f#$PROJECT_DIR/}\`"
      grep -n "Cubit(\|Bloc(" "$f" 2>/dev/null | grep -v "//" | head -3 | while IFS= read -r line; do
        info "    \`$line\`"
      done
    done <<< "$DUAL_WIRING"
  else
    info "✅ No dual wiring detected"
  fi
else
  info "❌ No service_locator.dart / injection.dart found"
fi

# ── 7. Cubit coupling analysis ──────────────────────────────
h2 "Cubit coupling analysis"

# Count cubits per feature
if [[ -d "$FEATURES_DIR" ]]; then
  info "**Cubit count per feature** (>2 warrants review):"
  while IFS= read -r feat; do
    name=$(basename "$feat")
    count=$(find "$feat" -name "*_cubit.dart" -o -name "*_bloc.dart" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 2 ]]; then
      info "- ⚠️  **$name**: $count cubits/blocs — consider consolidating"
    else
      info "- ✅ $name: $count"
    fi
  done < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# Cubit-to-cubit dependencies (constructor injection of one cubit into another)
info ""
info "**Cubit-to-cubit dependencies** (should be 0 — use domain services instead):"
FOUND=0
while IFS= read -r f; do
  base=$(basename "$f")
  # Only check cubit/bloc files
  if echo "$base" | grep -qE '_cubit\.dart|_bloc\.dart'; then
    # Look for other Cubit/Bloc types in constructor params
    matches=$(grep -n "final.*Cubit\|final.*Bloc\b" "$f" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      info "- ⚠️  \`${f#$PROJECT_DIR/}\`:"
      while IFS= read -r line; do
        info "  \`$line\`"
      done <<< "$matches"
      FOUND=1
    fi
  fi
done < <(dart_files)
[[ "$FOUND" -eq 0 ]] && info "✅ None detected"

# ── 8. Agent tool scatter ────────────────────────────────────
h2 "Agent / LLM tool scatter"

AGENT_DIR="$LIB_DIR/core/agent"
TOOLS_IN_AGENT=0
[[ -d "$AGENT_DIR/tools" ]] && TOOLS_IN_AGENT=$(find "$AGENT_DIR/tools" -name "*.dart" ! -name "*.g.dart" | wc -l | tr -d ' ')

# Tools living outside core/agent/tools/
SCATTERED=$(dart_files | xargs grep -l "AgentTool\|implements.*Tool\b\|FunctionTool" 2>/dev/null \
  | grep -v "$AGENT_DIR" \
  | grep -v "_test\.dart" || true)

if [[ -n "$SCATTERED" ]]; then
  info "⚠️  **Tool implementations found outside \`core/agent/tools/\`**:"
  while IFS= read -r f; do
    info "- \`${f#$PROJECT_DIR/}\`"
  done <<< "$SCATTERED"
elif [[ "$TOOLS_IN_AGENT" -gt 0 ]]; then
  info "✅ $TOOLS_IN_AGENT tool(s) correctly in \`core/agent/tools/\`"
else
  info "ℹ️  No agent tools detected (or not yet using AgentTool interface)"
fi

REGISTRY=$(dart_files | grep -E 'tool_registry\.dart' | head -1 || true)
if [[ -n "$REGISTRY" ]]; then
  info "✅ tool_registry.dart found: \`${REGISTRY#$PROJECT_DIR/}\`"
else
  info "⚠️  No \`tool_registry.dart\` found — tools may be registered ad-hoc"
fi

# ── 9. Routing ───────────────────────────────────────────────
h2 "Routing"
ROUTER_FILE=$(dart_files | grep -E 'app_router\.dart|router\.dart' | head -1 || true)
if [[ -n "$ROUTER_FILE" ]]; then
  rel="${ROUTER_FILE#$PROJECT_DIR/}"
  ROUTE_COUNT=$(grep -c 'path:' "$ROUTER_FILE" 2>/dev/null || echo 0)
  PATHS=$(grep "path:" "$ROUTER_FILE" 2>/dev/null | sed "s/^[[:space:]]*//" | tr '\n' ' ' || true)
  info "✅ \`$rel\` — $ROUTE_COUNT route(s)"
  info "$PATHS"
  STRAY_ROUTER=$(dart_files | grep -v "core/router" \
    | xargs grep -l "GoRouter(" 2>/dev/null || true)
  [[ -n "$STRAY_ROUTER" ]] && info "⚠️ GoRouter defined outside core/router:" \
    && while IFS= read -r f; do info "- \`${f#$PROJECT_DIR/}\`"; done <<< "$STRAY_ROUTER"
else
  info "❌ No router file found"
fi

# ── 10. Test coverage ─────────────────────────────────────────
h2 "Test coverage"
TEST_DIR="$PROJECT_DIR/test"
if [[ -d "$TEST_DIR" ]]; then
  TOTAL=$(find "$TEST_DIR" -name "*_test.dart" | wc -l | tr -d ' ')
  BLOC=$(find "$TEST_DIR" \( -name "*cubit*_test.dart" -o -name "*bloc*_test.dart" \) | wc -l | tr -d ' ')
  WIDGET=$(find "$TEST_DIR" \( -name "*widget*_test.dart" -o -name "*screen*_test.dart" \) | wc -l | tr -d ' ')
  REPO=$(find "$TEST_DIR" \( -name "*repo*_test.dart" -o -name "*repository*_test.dart" \) | wc -l | tr -d ' ')
  info "Total: $TOTAL  |  BLoC/Cubit: $BLOC  |  Widget/Screen: $WIDGET  |  Repo: $REPO"
  if [[ -d "$FEATURES_DIR" ]]; then
    info ""
    while IFS= read -r feat; do
      FEAT_NAME=$(basename "$feat")
      COUNT=$(find "$TEST_DIR" -name "*${FEAT_NAME}*" 2>/dev/null | wc -l | tr -d ' ')
      [[ "$COUNT" -eq 0 ]] && info "- ❌ $FEAT_NAME (no tests)" \
                           || info "- ✅ $FEAT_NAME ($COUNT file(s))"
    done < <(find "$FEATURES_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  fi
else
  info "❌ No \`test/\` directory found"
fi

} > "$OUT_FILE"

echo "✅ Pre-analysis written to: $OUT_FILE"
