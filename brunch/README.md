# Brunch - Declarative Home Manager for Brioche

Brunch is a tool for declaratively managing your Linux desktop environment using Brioche's TypeScript DSL. It provides Nix-like generation management for desktop applications and other XDG resources.

## Quick Start

### 1. Build the Brunch activator

```bash
brioche install -p ./src
```

This builds the `brunch` CLI tool, and puts it in `~/.local/share/brioche/installed/bin/brunch`, which should be in the user's $PATH.

### 2. Create a brunch.bri configuration

In the `config` directory, create a `brunch.bri` file:

```typescript
import * as std from "std";
import { makeBrunch } from "brioche-packages/packages/brunch/desktop_apps.bri";

export default function() {
  // Create a simple runnable script
  const myApp = std.bashRunnable`
    echo "Hello from my app!"
  `;
  const myIcon = std.file("my-icon.svg");

  return makeBrunch({
    desktopApps: [
      {
        name: "my-app",
        executable: myApp,
        icon: myIcon,
        comment: "My awesome app",
        categories: ["Development"],
      },
    ],
  });
}
```

### 3. Apply

```bash
brunch apply ./config
```

This builds your project and creates a new generation, symlinking everything into your home directory.

### 4. List and manage generations

```bash
brunch list-generations
```

Output:
```
Brunch generations:
  Generation 1 (current)
  Generation 2
  Generation 3
```

To rollback to a previous generation, use `switch-generation`:
```bash
brunch switch-generation 2
```

This updates `current` and re-links desktop assets.

### Managing Config Files

Brunch can manage arbitrary config files in your home directory (or system-wide).

```typescript
const weztermConfig = Brioche.includeFile("./wezterm.lua");

export default function() {
  return makeBrunch({
    desktopApps: [...],
    files: {
      // Relative paths are relative to $HOME
      ".config/wezterm/wezterm.lua": weztermConfig,
      
      // Absolute paths are relative to the system root /
      // "/etc/foo.conf": fooConfig,
    },
  });
}
```

When you apply a new generation:
- New files are symlinked.
- Files removed from the configuration are automatically unlinked (cleaned up), provided they were managed by Brunch.

### Generation Management

Brunch manages state in `~/.local/state/brunch/`:

```
~/.local/state/brunch/
├── generations/
│   ├── 1/              # Generation 1
│   ├── 2/              # Generation 2
│   └── 3/              # Generation 3
└── current -> generations/3   # Points to latest generation
```

Each generation contains a copy of the Brioche output artifact with symlinks to the actual store paths.

### Switch Generation

```bash
brunch switch-generation 3
```

This updates the `current` symlink to point to the specified generation, allowing instant rollbacks.

### Commands

#### `brunch apply <PROJECT_PATH>`
Build and apply a Brioche project as a new generation.

#### `brunch list-generations`
List all generations with the current one marked.

#### `brunch switch-generation <GEN_NUM>`
Switch to a specific generation, updating the `current` symlink and re-linking desktop assets.

### Atomic Symlink Updates

The activator uses atomic symlink updates via `ln -s + mv` pattern:

1. Create a temporary symlink
2. Atomically rename it over the target using `rename()` syscall
3. This ensures the symlink always exists during updates (no window where it's missing)

### XDG Compliance

Brunch follows the XDG Base Directory specification:

- **State**: `~/.local/state/brunch/` (or `$XDG_STATE_HOME`)
- **Binaries**: `~/.local/bin/`
- **Desktop entries**: `~/.local/share/applications/` (or `$XDG_DATA_HOME/applications/`)
- **Icons**: `~/.local/share/icons/hicolor/scalable/apps/` (or `$XDG_DATA_HOME/icons/...`)

All resources are symlinked from the `current` generation, enabling instant rollbacks.

## API Reference

### `makeBrunch(config: BrunchConfig): std.Recipe<std.Directory>`

Build a complete Brunch configuration artifact.

```typescript
interface BrunchConfig {
  desktopApps?: BrunchDesktopApp[];
}
```

### `makeDesktopApps(apps: BrunchDesktopApp[]): std.Recipe<std.Directory>`

Create a directory containing desktop application files.

```typescript
interface BrunchDesktopApp {
  name: string;
  executable: std.RecipeLike<std.Directory>;  // A runnable directory (e.g., from std.bashRunnable, cargoBuild, etc.)
  icon: std.RecipeLike<std.File>;
  comment?: string;
  categories?: string[];
}
```

## Development

### Building the Activator into a local directory

```bash
brioche build -o out-brunch

### Project Structure

```
brioche-packages/packages/brunch/
├── project.bri              # Brioche package definition
├── desktop_apps.bri          # Desktop app helpers
├── activator/                # Rust CLI tool
│   ├── Cargo.toml
│   └── src/
│       ├── main.rs
│       └── commands/
│           ├── apply.rs
│           ├── list_generations.rs
│           └── switch_generation.rs
└── examples/                  # Sample configs
    └── simple_hello.bri
```

## Future Roadmap

- [x] Add `switch-generation` command for easy rollbacks
- [ ] Support for systemd units
- [x] Support for config files (`.config/`, `~/.bashrc`, etc.)
- [ ] Add `remove-generation` command to clean up old generations
- [ ] Add `diff` command to see changes between generations
- [ ] Support for non-asset resources (environment variables, PATH additions)
