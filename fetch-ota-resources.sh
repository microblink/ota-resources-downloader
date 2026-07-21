#!/usr/bin/env bash

set -euo pipefail

DEFAULT_PROVIDER_URL="https://blinkid-ota.devel.microblink.com"
DEFAULT_OUTPUT_DIR="./blinkid-ota-resources"
VERSIONS_ENDPOINT="api/v1/versions"
MANIFEST_FILENAME="ota-resources.json"

usage() {
  cat <<'USAGE'
Fetch BlinkID OTA resources from the OTA API service.

Usage:
  fetch-ota-resources.sh [recognizer-version] [output-dir] [provider-url]

Arguments:
  recognizer-version  BlinkID recognizer generic version. If omitted, you will
                      be prompted for it.
  output-dir          Directory where OTA files will be written.
                      Default: ./blinkid-ota-resources
  provider-url        OTA API provider base URL.
                      Default: https://blinkid-ota.devel.microblink.com

Examples:
  ./fetch-ota-resources.sh 1.2.3
  ./fetch-ota-resources.sh 1.2.3 ./ota https://blinkid-ota.microblink.com

The provider endpoint must expose:
  GET {provider-url}/api/v1/versions?generic_version={recognizer-version}

The output directory can be hosted directly through otaResources.resourcesLocation.
The script writes ota-resources.json next to the downloaded binaries so SDK
clients can discover dynamic OTA filenames without calling the OTA API service.
USAGE
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}" >&2
    exit 1
  fi
}

trim_trailing_slashes() {
  local value="$1"
  printf '%s' "${value%/}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_command curl
require_command jq

recognizer_version="${1:-}"
output_dir="${2:-${DEFAULT_OUTPUT_DIR}}"
provider_url="${3:-${DEFAULT_PROVIDER_URL}}"

if [[ -z "${recognizer_version}" ]]; then
  printf 'Recognizer version: '
  IFS= read -r recognizer_version
fi

if [[ -z "${recognizer_version}" ]]; then
  echo "Recognizer version is required." >&2
  exit 1
fi

provider_url="$(trim_trailing_slashes "${provider_url}")"
request_url="${provider_url}/${VERSIONS_ENDPOINT}"

mkdir -p "${output_dir}"
manifest_file="$(mktemp)"
normalized_manifest_file="$(mktemp)"
download_list_file="$(mktemp)"
resources_manifest_file="${output_dir}/${MANIFEST_FILENAME}"
trap 'rm -f "${manifest_file}" "${normalized_manifest_file}" "${download_list_file}"' EXIT

echo "Resolving OTA resources for recognizer version: ${recognizer_version}"
echo "Provider: ${provider_url}"
curl \
  --fail \
  --get \
  --location \
  --silent \
  --show-error \
  --data-urlencode "generic_version=${recognizer_version}" \
  "${request_url}" \
  --output "${manifest_file}"

jq '
  def filename:
    .db_file_name //
    .db_filename //
    .filename //
    (.db_download_link | split("?")[0] | split("/") | map(select(length > 0)) | last);

  [
    ["embedder_engine", .embedder_engine],
    ["template_engine", .template_engine],
    ["document_knowledge_engine", .document_knowledge_engine]
  ]
  | map(
      .[0] as $name
      | .[1] as $entry
      | if ($entry.db_download_link | type) != "string" or ($entry.db_download_link | length) == 0 then
          error("OTA response is missing \($name).db_download_link")
        elif ($entry.latest_version | type) != "string" or ($entry.latest_version | length) == 0 then
          error("OTA response is missing \($name).latest_version")
        else
          $entry
          | filename as $filename
          | if ($filename | type) != "string" or ($filename | length) == 0 then
              error("OTA response is missing \($name) filename")
            elif $filename == "." or $filename == ".." or ($filename | test("[/\\\\]")) then
              error("OTA response contains an unsafe \($name) filename")
            else
              {
                filename: $filename,
                version: $entry.latest_version,
                download_url: $entry.db_download_link
              }
            end
        end
    )
' "${manifest_file}" >"${normalized_manifest_file}"

jq -r --arg output_dir "${output_dir}" \
  '.[] | [.download_url, ($output_dir + "/" + .filename)] | @tsv' \
  "${normalized_manifest_file}" >"${download_list_file}"

jq '{ resources: map({ filename, version }) }' \
  "${normalized_manifest_file}" >"${resources_manifest_file}"

while IFS=$'\t' read -r download_url destination; do
  echo "Downloading $(basename "${destination}")"
  curl --fail --location --silent --show-error "${download_url}" --output "${destination}"
done <"${download_list_file}"

echo "OTA resources manifest written to: ${resources_manifest_file}"
echo "OTA resources written to: ${output_dir}"
