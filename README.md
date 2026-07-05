# helix-dired

A Dired-style file manager for Helix Steel/Scheme.

This plugin opens a generated Dired buffer for browsing files and directories,
marking multiple entries, and running file operations from Helix commands.

## Requirements

- Helix built with Steel support
- `cp`, `mv`, and `rm` available on `PATH`
- A Steel setup that loads plugin entry files from `helix.scm`

## Installation

With `helix-steel-plugin-manager`:

```scheme
(plugin-install "OWNER/helix-dired")
```

For a local checkout during development, install it with an explicit URL/path
supported by your plugin manager, or require `helix.scm` directly from your
Helix Steel config.

Expose the commands from your `helix.scm`:

```scheme
(require (only-in "path/to/helix-dired/helix.scm"
                  DIRED
                  DIRED-KEYBINDINGS
                  dired-install-keybindings
                  dired
                  dired-current-directory
                  dired-refresh
                  dired-open
                  dired-toggle
                  dired-mark
                  dired-unmark
                  dired-unmark-all
                  dired-create-file
                  dired-create-directory
                  dired-copy
                  dired-move
                  dired-paste
                  dired-rename
                  dired-delete))

(provide dired
         dired-current-directory
         dired-install-keybindings
         dired-refresh
         dired-open
         dired-toggle
         dired-mark
         dired-unmark
         dired-unmark-all
         dired-create-file
         dired-create-directory
         dired-copy
         dired-move
         dired-paste
         dired-rename
         dired-delete)
```

The plugin installs its Dired buffer keymap automatically when `:dired` opens.
If you want to install it eagerly during startup, add this to `init.scm` after
loading the plugin:

```scheme
(dired-install-keybindings)
```

Manual keymap setup is also possible:

```scheme
(require "cogs/keymaps.scm")
(require (only-in "path/to/helix-dired/helix.scm" DIRED DIRED-KEYBINDINGS))

(define dired-base (deep-copy-global-keybindings))
(merge-keybindings dired-base DIRED-KEYBINDINGS)
(set-global-buffer-or-extension-keymap (hash DIRED dired-base))
```

## Usage

Open Dired:

```text
:dired
:dired-current-directory
:dired /path/to/project
```

Default Dired commands:

| Key | Command | Description |
| --- | --- | --- |
| `ret` | `:dired-open` | Open file or toggle directory |
| `tab` | `:dired-toggle` | Expand/collapse directory |
| `g` | `:dired-refresh` | Refresh from disk |
| `m` | `:dired-mark` | Mark current entry |
| `u` | `:dired-unmark` | Unmark current entry |
| `U` | `:dired-unmark-all` | Clear all marks |
| `n f` | `:dired-create-file` | Create file |
| `n d` | `:dired-create-directory` | Create directory |
| `y` | `:dired-copy` | Stage marked/current entries for copy |
| `x` | `:dired-move` | Stage marked/current entries for move |
| `p` | `:dired-paste` | Paste staged entries into target directory |
| `r` | `:dired-rename` | Rename current entry |
| `D` | `:dired-delete` | Delete marked/current entries after confirmation |

If entries are marked, file operations use the marked entries. If no entries
are marked, they use the current line.

## Notes

- The generated Dired buffer is written to `/tmp/helix-dired`.
- Delete uses `rm -rf` after requiring the confirmation text `yes`.
- Copy and move use external `cp -R` and `mv`.
- The current implementation keeps one global Dired session at a time.
