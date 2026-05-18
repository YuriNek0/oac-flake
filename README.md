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
- Rewrites context references to the pinned OAC `/nix/store/.../.opencode/context` path by default, avoiding Home Manager symlink traversal issues
- Integrates with `programs.opencode` (auto-enables by default)
- Can add built-in OpenCode permission rules for the pinned OAC context path and project `.tmp` directory

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
- `rewriteContextReferences` + `contextReferencePath` (defaults to the pinned OAC store context path)
- `installAdditionalPaths` + `additionalPathsPrefix`
- `enableBuiltinPermissions` (default: `true`)
- `allowOacContextRead` (default: `true`, only used when built-in permissions are enabled)
- `allowTmpDirFullAccess` (default: `true`, only used when built-in permissions are enabled)

## Bootstrap context files

The module installs two registry-resolved bootstrap context files so OpenCode agents can discover
the context tree immediately:

- `$XDG_CONFIG_HOME/opencode/context/navigation.md`
- `$XDG_CONFIG_HOME/opencode/context/core/config/paths.json`

These files follow `targetRoot` and `layout.context`, but intentionally do **not** honor
`pathOverrides`. This keeps required context discovery files at their canonical locations.
User-provided `extraFiles` and `overrides` still merge after generated and bootstrap files, so
you can replace content at the final target path when needed.

By default, references inside generated files, including `paths.json`, point at the pinned OAC
source context directory, for example `/nix/store/...-source/.opencode/context`, rather than the
Home Manager-installed `$XDG_CONFIG_HOME/opencode/context` symlink tree. This preserves Nix
immutability while giving OpenCode a real store path for efficient context discovery. If you
explicitly want rewritten references to use config-home paths, set:

```nix
programs.opencode.oac.contextReferencePath = "${config.xdg.configHome}/opencode/context";
```

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

### 6) Built-in OpenCode permissions

By default, this module emits built-in OpenCode permission rules controlled by:

- `enableBuiltinPermissions` - master switch for OAC-generated permission rules
- `allowOacContextRead` - allow reads to the pinned OAC context path
- `allowTmpDirFullAccess` - allow project `.tmp` read/write access

This gives OpenCode access to the immutable OAC context tree used by generated context references
and `paths.json`, plus the project `.tmp` directory used for temporary working files.

You can keep the declarative OAC file installation while fully managing permissions yourself by
disabling the built-in rules and setting `programs.opencode.settings.permission` directly.

Disable all permission rules generated by this module with:

```nix
programs.opencode.oac.enableBuiltinPermissions = false;
```

### 7) Allow reading the pinned OAC context path

By default, this module also adds narrower permission rules for the OAC context reference path:

- allow reads to `/nix/store/.../.opencode/context`
- deny edits/writes to that directory
- require `ask` approval for shell commands targeting that directory

When enabled, the module adds rules equivalent to:

```nix
programs.opencode.settings.permission = {
  external_directory = {
    "/nix/store/.../.opencode/context" = "allow";
    "/nix/store/.../.opencode/context/**" = "allow";
  };
  read = {
    "/nix/store/.../.opencode/context" = "allow";
    "/nix/store/.../.opencode/context/**" = "allow";
  };
  edit = {
    "/nix/store/.../.opencode/context" = "deny";
    "/nix/store/.../.opencode/context/**" = "deny";
  };
  bash = {
    "* /nix/store/.../.opencode/context*" = "ask";
  };
};
```

This is applied with `mkDefault`, so you can still override the generated OpenCode settings
with your own `programs.opencode.settings.permission` values if needed.

This policy is only emitted when both `enableBuiltinPermissions` and `allowOacContextRead` are true.

Reference: https://opencode.ai/docs/permissions/#granular-rules-object-syntax

The generated OAC context rules target the same path used by `contextReferencePath`, which defaults
to the pinned OAC source context directory in the Nix store.

Disable just the OAC context read policy with:

```nix
programs.opencode.oac.allowOacContextRead = false;
```

### 8) Allow project `.tmp` read/write access

By default, this module also adds OpenCode permission rules that:

- allow reads to `.tmp`
- allow edits/writes to `.tmp`
- allow the built-in `ls` command patterns used to inspect `.tmp`
- allow the built-in `mkdir` command patterns used to create `.tmp` or directories inside `.tmp`
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
    "ls .tmp*" = "allow";
    "ls * .tmp*" = "allow";
    "ls \".tmp*" = "allow";
    "ls * \".tmp*" = "allow";
    "mkdir tmp*" = "allow";
    "mkdir * tmp*" = "allow";
    "mkdir \".tmp*" = "allow";
    "mkdir * \".tmp*" = "allow";
  };
};
```

This policy is only emitted when both `enableBuiltinPermissions` and `allowTmpDirFullAccess` are
true.

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
