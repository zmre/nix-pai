# README for the Nix Personal AI Infrastructure (PAI)

This is a flake that isn't meant to be run directly, but to instead serve as a configurable template and starting point.

This project started from Daniel Miessler's [Personal AI Infrastructure](http://github.com/danielmiessler/Personal_AI_Infrastructure/) and most of the concepts and files are directly out of there, though it's been overhauled and changed in a number of ways:

1. Does not default to giving all available permissions
2. Consistency of paths, assistant name, and so on
3. Found placeholders and made them configs in the flake
4. No hidden files or directories and no global config files; this is a fully sandboxed approach
5. Better secrets handling without API keys in `.env` files
6. Mostly removed the voice announcement stuff as I found it to be confused between different implementations and not something that I could easily toggle on and off. May revisit this later.
7. I removed a lot of the session capture and summarization stuff and may revisit later when I better understand why I'd want that.

I've also added in some skills from skill marketplaces and anthropic examples.

The goal here is ultimately to be less claude-specific and to enable more privacy-first options while using a shared filesystem-first set of prompts and helpers. This flake makes multiple AI tools available and available to each other (since there are research skills that call out, for example, to gemini from claude).

## Secrets Setup

For your assistant and claude, you will be prompted to login on first use. Every time you start one of the main AI tools like `claude`, `codex`, or `gemini`, they will get an environment with various API keys loaded into it.  You can use the `extraSecrets` config to add more things to the environment that are pulled from a local keychain.

The two currently supported keychains are `security` on MacOS, which uses the Apple Keychain.  If you're on Mac, you'll want to add your secrets like this:

`security add-generic-password -a $USERNAME -s keyname -w`

If you're on Linux, we use `secret-tool` which comes from the gnome-keyring, but can run fine without gnome and weirdly, at least on nix, requires you to install `libsecret`.  To add secrets to that, use this command:

`secret-tool store --label "Your Key Description" api keyname`

In both cases you'll be prompted for the password (API key).

Here are the ones we have baked in. If you don't have any, the env var will be blank and no harm done:

* openaikey
* reftoolskey

(I've made the list of secrets shorter as I realize how to log in to some tools with oauth. The reason to prefer oauth here is purely performance: each password fetch attempt slows down startup.)

To be clear: you should be able to use your assistant just fine without doing any of this.

## Usage

This project uses [flake-parts](https://flake.parts) to make the flake modular and configurable. There may be a way to use it without using flake-parts (it's still just the standard flake system after all), but the example below demonstrates how to use flake-parts to add some basic customization.

### Basic Example

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    paiTemplate.url = "github:zmre/nix-pai";
    paiTemplate.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{flake-parts, paiTemplate, ...}:
    flake-parts.lib.mkFlake {
      inherit inputs;
    } {
      # pick the arch where you want this to work
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      # Pull in the base module
      imports = [paiTemplate.flakeModules.default];

      # Customize (note: this is not a comprehensive view of the options)
      pai = {
        assistantName = "Jeeves";
        assistantColor = "red";
        commandName = "jv"; # this is the command you'll run from the terminal
        userFullName = "Patrick Walsh";
        extraSkills = [./skills];
      };

      perSystem = { config, lib, ...}: {
        packages.default = config.packages.pai;
        apps.default = {
          type = "app";
          program = lib.getExe config.packages.pai;
        };
      };
    };
}
```

### Advanced Configuration

Both `claudeSettings` and `mcpServers` are Nix options that generate `settings.json` and `mcp.json` at build time. You can override defaults or add to them:

```nix
{
  pai = {
    assistantName = "Iris";
    commandName = "i";

    # Override or extend Claude Code settings
    claudeSettings = {
      outputStyle = "explanatory";
      companyAnnouncements = ["Welcome! I'm Iris, ready to help."];
      permissions = {
        defaultMode = "default";
        # Add to default allow list
        allow = lib.mkAfter [
          "Bash(docker:*)"
          "Bash(kubectl:*)"
        ];
      };
    };

    # Override or extend MCP servers
    # Default includes Ref server for documentation lookup
    mcpServers = {
      # Add a new MCP server
      playwright = {
        type = "stdio";
        command = "npx";
        args = ["-y" "@anthropic/mcp-playwright"];
      };
      # Override default Ref server settings (optional)
      Ref = {
        type = "http";
        url = "https://api.ref.tools/mcp";
        headers = {
          "x-ref-api-key" = "\${REF_TOOLS_KEY}";
        };
      };
    };
  };
}
```

### MCP Server Configuration

MCP servers can be configured with these options:

| Option | Type | Description |
|--------|------|-------------|
| `type` | string | Server type: `"http"` or `"stdio"` |
| `url` | string | URL for http-type servers |
| `command` | string | Command for stdio-type servers |
| `args` | list | Arguments for stdio-type servers |
| `headers` | attrs | HTTP headers (for http-type) |
| `env` | attrs | Environment variables (for stdio-type) |

Both `@paiBasePath@` and `@assistantName@` are valid placeholders that get substituted at build time.

### Included Tools

With that, you can just `nix run` your flake or you can include the flake in your OS build or as if it is just a single program.

But it isn't just a single program, but a collection of AI tools. So if you install it, you'll have all of these commands (and more) in your path:

* `jv`, (or whatever you called your assistant -- this is how you call claude with all the extra prompts and instructions setup),
  * To be clear, `jv` is just an example; I use `i`, short for `iris`, and you can do whatever you want.
* `claude`, (just vanilla or global config stuff),
* `codex`,
* `gemini`,
* `fabric`,
* and some others.

No worries if you don't use them, they're taking up space but inert. Or you can toggle them off in the config.
