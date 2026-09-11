# OTA Resources Downloader

Downloads BlinkID OTA resource binaries and creates an `ota-resources.json`
manifest that SDK clients can use to discover the downloaded files.

## Requirements

- Bash
- `curl`
- `jq`

## Usage

Make the script executable once:

```sh
chmod +x fetch-ota-resources.sh
```

Run it with a BlinkID recognizer version:

```sh
./fetch-ota-resources.sh <recognizer-version> [output-dir] [provider-url]
```

If the recognizer version is omitted, the script prompts for it. The defaults
are:

- Output directory: `./blinkid-ota-resources`
- Provider URL: `https://blinkid-ota.devel.microblink.com`

Examples:

```sh
./fetch-ota-resources.sh 1.2.3
./fetch-ota-resources.sh 1.2.3 ./ota https://blinkid-ota.microblink.com
```

Use `./fetch-ota-resources.sh --help` for the complete command reference.

## Output

The output directory contains the downloaded engine binaries and an
`ota-resources.json` manifest. The default output directory is ignored by Git.

Each manifest entry contains the downloaded file's byte length:

```json
{
  "resources": [
    {
      "filename": "serialized-embedder-database.bin",
      "version": "1.0.14",
      "contentLength": 3831312
    }
  ]
}
```
