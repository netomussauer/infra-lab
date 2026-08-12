#!/usr/bin/env bash
# omniroute-upload.sh
#
# Faz upload do LAB-CONTEXT.md gerado (build/LAB-CONTEXT.md) para o OmniRoute
# via `/v1/files` — depois qualquer host de dev baixa via `lab-context-fetch.sh`.
#
# Idempotente:
#   1. Lista arquivos existentes filtrando por `filename == lab-context.md`
#   2. Deleta as versões anteriores
#   3. Sobe a versão nova com purpose=assistants
#   4. Persiste o file_id novo em context/build/.file-id (versionável opcional)
#
# Requer:
#   - OMNIROUTE_URL e OMNIROUTE_API_KEY em ~/.env.omniroute
#   - build/LAB-CONTEXT.md gerado (rode build-lab-context.py antes)
#   - jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_FILE="${SCRIPT_DIR}/build/LAB-CONTEXT.md"
FILE_ID_MARKER="${SCRIPT_DIR}/build/.file-id"
UPLOAD_NAME="lab-context.md"

# --- env ---
if [ -f "${HOME}/.env.omniroute" ]; then
  # shellcheck disable=SC1091
  source "${HOME}/.env.omniroute"
fi
: "${OMNIROUTE_URL:?OMNIROUTE_URL não definido em ~/.env.omniroute}"
: "${OMNIROUTE_API_KEY:?OMNIROUTE_API_KEY não definido em ~/.env.omniroute}"

if [ ! -f "${BUILD_FILE}" ]; then
  echo "ERRO: ${BUILD_FILE} não existe. Rode primeiro: python3 build-lab-context.py" >&2
  exit 1
fi

command -v python3 >/dev/null || { echo "ERRO: python3 não instalado" >&2; exit 1; }

echo "== omniroute-upload =="
echo "endpoint: ${OMNIROUTE_URL}"
echo "arquivo : $(du -h "${BUILD_FILE}" | cut -f1)  (${BUILD_FILE})"

# --- 1) Listar files existentes com o mesmo filename ---
echo
echo "== procurando uploads anteriores =="
existing_ids=$(curl -sS --max-time 10 \
  -H "Authorization: Bearer ${OMNIROUTE_API_KEY}" \
  "${OMNIROUTE_URL}/v1/files" \
  | python3 -c "
import sys, json
name = '${UPLOAD_NAME}'
for f in json.load(sys.stdin).get('data', []):
    if f.get('filename') == name:
        print(f['id'])")

if [ -n "${existing_ids}" ]; then
  for id in ${existing_ids}; do
    echo "  deletando ${id}"
    curl -sS --max-time 10 -X DELETE \
      -H "Authorization: Bearer ${OMNIROUTE_API_KEY}" \
      "${OMNIROUTE_URL}/v1/files/${id}" > /dev/null
  done
else
  echo "  (nenhum upload anterior encontrado)"
fi

# --- 2) Upload novo ---
echo
echo "== upload novo =="
# Renomear temporariamente pro filename fixo (lab-context.md)
TMP_UPLOAD="$(mktemp -d)/${UPLOAD_NAME}"
cp "${BUILD_FILE}" "${TMP_UPLOAD}"

response=$(curl -sS --max-time 30 -X POST "${OMNIROUTE_URL}/v1/files" \
  -H "Authorization: Bearer ${OMNIROUTE_API_KEY}" \
  -F "purpose=assistants" \
  -F "file=@${TMP_UPLOAD}")

rm -rf "$(dirname "${TMP_UPLOAD}")"

read -r file_id bytes <<< "$(echo "${response}" | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(r.get('id', ''), r.get('bytes', 0))")"

if [ -z "${file_id}" ]; then
  echo "ERRO: upload falhou. Resposta:" >&2
  echo "${response}" >&2
  exit 1
fi

echo "${file_id}" > "${FILE_ID_MARKER}"

echo "  file_id: ${file_id}"
echo "  bytes  : ${bytes}"
echo "  marker : ${FILE_ID_MARKER}"

echo
echo "OK — corpus atualizado no OmniRoute. Hosts que rodarem lab-context-fetch.sh"
echo "pegam a versão nova automaticamente."
