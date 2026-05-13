# oac-flake

Declarative Nix/Home Manager integration for [OpenAgentsControl (OAC)](https://github.com/darrenhinde/OpenAgentsControl).

This flake reproduces installer profile logic (`essential`, `developer`, `business`, `full`, `advanced`) using pinned Nix inputs instead of mutable shell installation.

## What it does

- Pulls OAC from a pinned flake input (`inputs.oac`, `flake = false`)
- Reads `registry.json`
- Expands profile components + `context:*` wildcards
- Resolves transitive dependencies
- Emits bootstrap context specs (`context:root-navigation` and `context:context-paths-config`) from the registry so context discovery works immediately
- Installs resolved files into `$XDG_CONFIG_HOME/opencode/...` via Home Manager
- Integrates with `programs.opencode` (auto-enables by default)
- Adds a default OpenCode policy that explicitly denies broader `~/.config` access
- Can opt back into a narrower `~/.config/opencode` read policy with `programs.opencode.oac.denyHomeConfigRead = false;`
- Adds a default OpenCode policy that allows read/write access to the project `.tmp` directory, while requiring approval for most bash commands targeting it

## Add as flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    oac-flake.url = "path:/path/to/OpenAgentsControl/oac-flake";
    # or your own repo:
    # oac-flake.url = "github:you/oac-flake";
  };
}
```

## Home Manager usage

```nix
{ inputs, ... }:
{
  imports = [
    inputs.oac-flake.homeManagerModules.oac
  ];

  programs.opencode = {
    enable = true;

    # standard Home Manager opencode settings still work
    settings = {
      model = "anthropic/claude-sonnet-4-20250514";
      autoupdate = false;
    };

    oac = {
      enable = true;
      profile = "developer";
    };
  };
}
```

## Options (high level)

`programs.opencode.oac.*`

- `enable` (bool)
- `profile` (`essential|developer|business|full|advanced|null`)
- `components` (list of extra component specs)
- `excludeComponents` (list of specs to remove)
- `includeDependencies` (bool)
- bootstrap context specs `context:root-navigation` and `context:context-paths-config` are always included unless explicitly excluded
- bootstrap files are installed at canonical context paths and bypass `pathOverrides` so discovery files cannot be relocated accidentally
- bootstrap assertions are component-driven: they validate registry/source resolution and that each resolved source path exists under `${source}`
- `source` (optional alternate OAC source path)
- `targetRoot` (default: `opencode`)
- `layout.*` path segment remapping (`agent`, `command`, `context`, `tool`, `plugin`, `skills`, `config`)
- `pathOverrides` (exact source-path -> destination-path override)
- `extraFiles` / `overrides` (user-provided file/text additions)
- `rewriteContextReferences` + `contextReferencePath`
- `installAdditionalPaths` + `additionalPathsPrefix`
- `allowOpenCodeConfigRead` (default: `true`, merged with `denyHomeConfigRead`)
- `denyHomeConfigRead` (default: `true`)
- `allowTmpDirFullAccess` (default: `true`)

## Bootstrap context files

The module installs two registry-resolved bootstrap context files so OpenCode agents can discover
the context tree immediately:

- `$XDG_CONFIG_HOME/opencode/context/navigation.md`
- `$XDG_CONFIG_HOME/opencode/context/core/config/paths.json`

These files follow `targetRoot` and `layout.context`, but intentionally do **not** honor
`pathOverrides`. This keeps required context discovery files at their canonical locations.
User-provided `extraFiles` and `overrides` still merge after generated and bootstrap files, so
you can replace content at the final target path when needed.

## Installer compatibility

This module mirrors upstream `install.sh` registry behavior for profile expansion,
`context:*` wildcard expansion, transitive dependency resolution, non-`.md` context IDs such as
`core/config/paths.json`, and multi-file components.

Intentional differences from `install.sh`:

- Bootstrap contexts are always emitted by this module; the shell installer receives them only
  when selected components or dependencies include them.
- `advanced` profile `additionalPaths` are opt-in with `installAdditionalPaths`; the shell
  installer reports those paths for manual download.

## Simple customization examples

### 1) Use `business` profile and add one dev command

```nix
programs.opencode.oac = {
  enable = true;
  profile = "business";
  components = [ "command:commit" ];
};
```

### 2) Exclude a plugin

```nix
programs.opencode.oac = {
  enable = true;
  profile = "full";
  excludeComponents = [ "plugin:notify" ];
};
```

### 3) Custom directory structure

```nix
programs.opencode.oac = {
  enable = true;
  profile = "developer";

  layout = {
    agent = "agents";
    command = "commands";
    context = "context";
    tool = "tools";
    plugin = "plugins";
    skills = "skills";
    config = "config";
  };

  pathOverrides = {
    ".opencode/agent/core/openagent.md" = "agents/openagent.md";
  };
};
```

### 4) Override one upstream file with your own

```nix
programs.opencode.oac = {
  enable = true;
  profile = "developer";

  overrides = {
    "agent/core/openagent.md" = ./my-openagent.md;
  };
};
```

### 5) Use a custom OAC source (fork)

```nix
{
  inputs.oac-fork = {
    url = "github:yourname/OpenAgentsControl/your-branch";
    flake = false;
  };

  # ...

  programs.opencode.oac.source = inputs.oac-fork;
}
```

### 6) Home config sandbox defaults

By default, this module emits both of these OpenCode permission policies:

- a broad deny for `~/.config`
- a narrower OpenCode-specific override for `~/.config/opencode`

This keeps the broader home config sandbox in place while still allowing OpenCode to read its
own global config directory.

The broad home-config policy blocks access to the broader home config directory:

- deny external-directory access to `~/.config`
- deny reads from `~/.config`
- deny edits/writes to `~/.config`
- deny shell commands targeting `~/.config`

When enabled, the module adds rules equivalent to:

```nix
programs.opencode.settings.permission = {
  external_directory = {
    "~/.config" = "deny";
    "~/.config/**" = "deny";
  };
  read = {
    "~/.config" = "deny";
    "~/.config/**" = "deny";
  };
  edit = {
    "~/.config" = "deny";
    "~/.config/**" = "deny";
  };
  bash = {
    "* ~/.config*" = "deny";
    "* $HOME/.config*" = "deny";
  };
};
```

The module also applies matching rules for the resolved `$XDG_CONFIG_HOME` path, so this
still works when your config directory is not literally `~/.config`.

Disable that default with:

```nix
programs.opencode.oac.denyHomeConfigRead = false;
```

### 7) Allow reading OpenCode's global config directory

By default, this module also adds narrower permission rules for OpenCode's own config directory:

- allow reads to `~/.config/opencode`
- require `ask` approval for edits/writes to that directory
- require `ask` approval for shell commands targeting that directory

When enabled, the module adds rules equivalent to:

```nix
programs.opencode.settings.permission = {
  external_directory = {
    "~/.config/opencode" = "allow";
    "~/.config/opencode/**" = "allow";
  };
  read = {
    "~/.config/opencode" = "allow";
    "~/.config/opencode/**" = "allow";
  };
  edit = {
    "~/.config/opencode" = "ask";
    "~/.config/opencode/**" = "ask";
  };
  bash = {
    "* ~/.config/opencode*" = "ask";
    "* $HOME/.config/opencode*" = "ask";
  };
};
```

This is applied with `mkDefault`, so you can still override the generated OpenCode settings
with your own `programs.opencode.settings.permission` values if needed.

When both defaults are enabled, the generated config contains both the broad deny and the narrow
OpenCode-specific rules. This relies on OpenCode's documented granular rule matching behavior:
rules are evaluated by pattern match, with the last matching rule winning.

Reference: https://opencode.ai/docs/permissions/#granular-rules-object-syntax

That means broader patterns should come first and more specific patterns after them. In this
module, the `~/.config` deny rules are emitted before the narrower `~/.config/opencode` rules,
so `~/.config/opencode` remains readable while the rest of `~/.config` stays denied.

Disable just the narrower OpenCode override with:

```nix
programs.opencode.oac.allowOpenCodeConfigRead = false;
```

Disable both home-config policies with:

```nix
programs.opencode.oac = {
  denyHomeConfigRead = false;
  allowOpenCodeConfigRead = false;
};
```

### 8) Allow project `.tmp` read/write access

By default, this module also adds OpenCode permission rules that:

- allow reads to `.tmp`
- allow edits/writes to `.tmp`
- require `ask` approval for bash commands targeting `.tmp`
- allow `mkdir` commands that create `.tmp` or directories inside `.tmp`
- include rules for both `.tmp` and `.tmp/**`

When enabled, the module adds rules equivalent to:

```nix
programs.opencode.settings.permission = {
  read = {
    ".tmp" = "allow";
    ".tmp/**" = "allow";
  };
  edit = {
    ".tmp" = "allow";
    ".tmp/**" = "allow";
  };
  bash = {
    "* .tmp*" = "ask";
    "mkdir* .tmp*" = "allow";
  };
};
```

Disable that default with:

```nix
programs.opencode.oac.allowTmpDirFullAccess = false;
```

## Updating

Nix handles updates through lock files.

```bash
nix flake update oac-flake
# or update just OAC input in this flake:
nix flake lock --update-input oac
```

Then rebuild Home Manager / NixOS as usual.
