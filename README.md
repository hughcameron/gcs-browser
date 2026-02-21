# gcs-yazi

Browse, preview, and navigate Google Cloud Storage from [yazi](https://yazi-rs.github.io/).

Creates a temporary directory at `/tmp/yazi-gcs/` with placeholder files mirroring
the GCS bucket structure. Navigate with normal yazi keybindings — subdirectories
are auto-populated as you enter them.

## Features

- **Browse** — press `gs` to pick a bucket and navigate its contents
- **Header indicator** — shows `☁ gs://bucket/path/` when inside a GCS directory
- **Auto-populate** — entering a subdirectory automatically fetches its contents from GCS
- **File preview** — preview pane shows the first ~800 bytes of GCS objects
- **Copy path** — works with [copy-volume-path](https://github.com/hughcameron/config) to produce `gs://` URIs

## Requirements

- [yazi](https://yazi-rs.github.io/) 26.x+
- [gcloud CLI](https://cloud.google.com/sdk/gcloud) (`gcloud storage ls`, `gcloud storage cat`)
- Authenticated: `gcloud auth login`

## Installation

```sh
ya pack -a hughcameron/gcs-yazi
```

## Configuration

### 1. init.lua

Add the setup call to `~/.config/yazi/init.lua`:

```lua
require("gcs-yazi"):setup()
```

With options:

```lua
require("gcs-yazi"):setup({
    -- Override gcloud path if not in PATH (default: "gcloud")
    gcloud_path = "/opt/homebrew/bin/gcloud",
})
```

### 2. yazi.toml

Register the previewer for GCS temp files in `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
    # ... your other previewers ...
    { url = "/tmp/yazi-gcs/**", run = "gcs-yazi" },
]
```

### 3. keymap.toml

Add the `gs` keybinding to `~/.config/yazi/keymap.toml`:

```toml
[[mgr.prepend_keymap]]
on   = ["g", "s"]
run  = "plugin gcs-yazi"
desc = "Browse GCS buckets"
```

## Usage

1. Press `gs` from any directory to browse GCS
2. If multiple buckets exist, pick one from the list
3. Navigate normally with `l` (enter) and `h` (back)
4. Subdirectories auto-populate as you enter them
5. Hover a file to see its content in the preview pane
6. Press `gs` again while inside a GCS directory to refresh

## How it works

The plugin creates a temporary directory at `/tmp/yazi-gcs/<bucket>/` with empty
files and directories matching the GCS structure. This lets yazi treat it as a
normal filesystem while the plugin handles fetching content on demand.

- `entry()` — bucket picker + directory population
- `setup()` — header indicator + `cd` event hook for auto-populate
- `peek()` — fetches first 800 bytes via `gcloud storage cat` for preview

## License

MIT
