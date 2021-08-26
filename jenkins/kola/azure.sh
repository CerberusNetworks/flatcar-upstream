#!/bin/bash
set -ex

rm -rf *.tap _kola_temp*

NAME="jenkins-${JOB_NAME##*/}-${BUILD_NUMBER}"

if [[ "${BOARD}" == "arm64-usr" ]]; then
  echo "Unsupported board"
  exit 1
fi

if [[ "${KOLA_TESTS}" == "" ]]; then
  KOLA_TESTS="*"
fi

if [[ "${AZURE_MACHINE_SIZE}" != "" ]]; then
  AZURE_MACHINE_SIZE_OPT="--azure-size=${AZURE_MACHINE_SIZE}"
fi

# If the OFFER is empty, it should be treated as the basic offering.
if [[ "${OFFER}" == "" ]]; then
  OFFER="basic"
fi

if [ "${BLOB_URL}" = "" ]; then
  exit 0
fi

# Do not expand the kola test patterns globs
set -o noglob
timeout --signal=SIGQUIT 20h bin/kola run \
    --parallel="${PARALLEL}" \
    --basename="${NAME}" \
    --board="${BOARD}" \
    --channel="${GROUP}" \
    --platform=azure \
    --offering="${OFFER}" \
    --azure-blob-url="${BLOB_URL}" \
    --azure-location="${LOCATION}" \
    --azure-profile="${AZURE_CREDENTIALS}" \
    --azure-auth="${AZURE_AUTH_CREDENTIALS}" \
    --tapfile="${JOB_NAME##*/}.tap" \
    --torcx-manifest=torcx_manifest.json \
    ${AZURE_MACHINE_SIZE_OPT} \
    ${AZURE_HYPER_V_GENERATION:+--azure-hyper-v-generation=${AZURE_HYPER_V_GENERATION}} \
    ${KOLA_TESTS}
set +o noglob
