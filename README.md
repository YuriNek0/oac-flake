# oac-flake

Declarative Nix/Home Manager integration for [OpenAgentsControl (OAC)](https://github.com/darrenhinde/OpenAgentsControl).

This flake reproduces installer profile logic (`essential`, `developer`, `business`, `full`, `advanced`) using pinned Nix inputs instead of mutable shell installation.

## What it does

- Pulls OAC from a pinned flake input (`inputs.oac`, `flake = false`)
- Reads `registry.json`
- Expands profile components + `context:*` wildcards
- Resolves transitive dependencies
- Installs resolved files into `$XDG_CONFIG_HOME/opencode/...` via Home Manager
- Integrates with `programs.opencode` (auto-enables by default)
- Adds a default OpenCode policy that allows reading `~/.config/opencode` but requires approval for edits, writes, and shell commands targeting it

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
- `source` (optional alternate OAC source path)
- `targetRoot` (default: `opencode`)
- `layout.*` path segment remapping (`agent`, `command`, `context`, `tool`, `plugin`, `skills`, `config`)
- `pathOverrides` (exact source-path -> destination-path override)
- `extraFiles` / `overrides` (user-provided file/text additions)
- `rewriteContextReferences` + `contextReferencePath`
- `installAdditionalPaths` + `additionalPathsPrefix`
- `allowOpenCodeConfigRead` (default: `true`)

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

### 6) Allow reading OpenCode's global config directory

By default, this module adds OpenCode permission rules that:

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

Disable that default with:

```nix
programs.opencode.oac.allowOpenCodeConfigRead = false;
```

## Updating

Nix handles updates through lock files.

```bash
nix flake update oac-flake
# or update just OAC input in this flake:
nix flake lock --update-input oac
```

Then rebuild Home Manager / NixOS as usual.
