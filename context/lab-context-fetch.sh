#!/usr/bin/env bash
# lab-context-fetch.sh
#
# Baixa o corpus consolidado do lab (LAB-CONTEXT.md) do OmniRoute e salva em
# ~/.lab-context.md. Idempotente: se o hash local == remoto, não sobrescreve.
#
# Este script é o que TODOS os hosts de dev (Continue.dev, Open-WebUI custom
# prompt, futuros wrappers) executam para sincronizar o contexto.
#
# Uso (bootstrap num host novo):
#   curl -O https://raw.githubusercontent.com/netomussauer/infra-lab/main/context/lab-context-fetch.sh
#   chmod +x lab-context-fetch.sh
#   ./lab-context-fetch.sh
#
# Depois, aponte o `systemMessage` (ou equivalente) do seu cliente LLM para
# o conteúdo de ~/.lab-context.md.
#
# Configuração — endpoint e key vem de ~/.env.omniroute:
#   OMNIROUTE_URL=http://192.168.1.117:20128
#   OMNIROUTE_API_KEY=sk-...

set -euo pipefail

CACHE_FILE="${HOME}/.lab-context.md"
UPLOAD_NAME="lab-context.md"

# --- env ---
if [ -f "${HOME}/.env.omniroute" ]; then
  # shellcheck disable=SC1091
  source "${HOME}/.env.omniroute"
fi
: "${OMNIROUTE_URL:?OMNIROUTE_URL não definido — crie ~/.env.omniroute}"
: "${OMNIROUTE_API_KEY:?OMNIROUTE_API_KEY não definido — crie ~/.env.omniroute}"

command -v curl >/dev/null || { echo "ERRO: curl não instalado" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERRO: python3 não instalado" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERRO: sha256sum não instalado" >&2; exit 1; }

# --- 1) Achar file_id atual pelo filename ---
file_id=$(curl -sS --max-time 10 \
  -H "Authorization: Bearer ${OMNIROUTE_API_KEY}" \
  "${OMNIROUTE_URL}/v1/files" \
  | python3 -c "
import sys, json
name = '${UPLOAD_NAME}'
for f in json.load(sys.stdin).get('data', []):
    if f.get('filename') == name:
        print(f['id'])
        break")

if [ -z "${file_id}" ]; then
  echo "ERRO: não encontrei ${UPLOAD_NAME} no OmniRoute. Rode omniroute-upload.sh no repo do lab primeiro." >&2
  exit 2
fi

# --- 2) Baixar content novo pra tmp ---
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
http_code=$(curl -sS --max-time 30 -o "${tmp}" -w "%{http_code}" \
  -H "Authorization: Bearer ${OMNIROUTE_API_KEY}" \
  "${OMNIROUTE_URL}/v1/files/${file_id}/content")

if [ "${http_code}" != "200" ]; then
  echo "ERRO: download falhou (HTTP ${http_code})" >&2
  exit 3
fi

new_hash=$(sha256sum "${tmp}" | cut -d' ' -f1)
old_hash=""
if [ -f "${CACHE_FILE}" ]; then
  old_hash=$(sha256sum "${CACHE_FILE}" | cut -d' ' -f1)
fi

if [ "${new_hash}" = "${old_hash}" ]; then
  size=$(du -h "${CACHE_FILE}" | cut -f1)
  echo "SEM MUDANÇAS · ${CACHE_FILE} (${size}, sha256=${new_hash:0:12})"
  exit 0
fi

mv "${tmp}" "${CACHE_FILE}"
trap - EXIT
chmod 600 "${CACHE_FILE}"
size=$(du -h "${CACHE_FILE}" | cut -f1)

if [ -z "${old_hash}" ]; then
  prev_short="(nenhum cache anterior)"
else
  prev_short="${old_hash:0:12}..."
fi

echo "ATUALIZADO · ${CACHE_FILE}"
echo "  size    : ${size}"
echo "  sha256  : ${new_hash:0:12}...  (era ${prev_short})"
echo "  file_id : ${file_id}"
echo
echo "Configure seu cliente LLM para injetar este arquivo como system prompt."
echo "  Continue.dev: aponte 'systemMessage' para o path acima."
echo "  Open-WebUI  : Admin → Settings → Interface → Default Prompt (cole conteúdo)."
