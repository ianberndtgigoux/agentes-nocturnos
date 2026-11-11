#!/bin/bash
# Runner mínimo de un agente desatendido. Arma las tres capas de contención
# e invoca `claude -p`. Extraído de un sistema privado en producción.
#
#   correr-agente.sh <tipo> [periodo-forzado]
#
# El período se resuelve ACÁ, no en el prompt: una fecha mal calculada por
# el modelo es un dato inventado.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TIPO="${1:?falta <tipo>}"
FORZADO="${2:-}"
HOY="$(date +%F)"
REGISTRO="$REPO/registro"; mkdir -p "$REGISTRO"

PROMPT="$REPO/prompts/$TIPO.md"
[ -f "$PROMPT" ] || { echo "no existe $PROMPT" >&2; exit 1; }

# 1. El período, resuelto fuera del modelo y pasado como dato.
CTX=$(npx tsx "$REPO/scripts/calcular-periodo.ts" "$TIPO" "$HOY" "$FORZADO")
while IFS='=' read -r k v; do [ -n "$k" ] && eval "CTX_$k=\$v"; done <<< "$CTX"

# 2. Las tres capas de contención. Ninguna depende del criterio del modelo.
#    - permisos por herramienta, con deny explícito sobre el repo
#    - set de herramientas recortado: sin Task, sin WebFetch, sin WebSearch
#    - MCP apagados: --strict-mcp-config SIN --mcp-config
claude -p "$(cat "$PROMPT")

PERIODO: ${CTX_PERIODO}
DESDE: ${CTX_DESDE}
HASTA: ${CTX_HASTA}" \
  --settings "$REPO/permisos-agente.json" \
  --tools "Bash,Read,Write" \
  --strict-mcp-config \
  2>&1 | tee "$REGISTRO/$TIPO-$CTX_PERIODO.log"

echo "tipo=$TIPO periodo=$CTX_PERIODO estado=ok" >> "$REGISTRO/registro.log"
