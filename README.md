# ceramic (via haxelib)

Install ceramic via haxelib in home directory (USERPROFILE on windows, HOME on mac/linux):

```bash
haxelib install ceramic
haxelib run ceramic setup
```

Then once installed, run ceramic this way:

```bash
haxelib run ceramic
```

If you did choose to install global `ceramic` command during setup, you can simply type:

```bash
ceramic
```

## Options

**--cwd {path}**

Specify a custom working directory (can be used to install/update ceramic at a specific location).
Usage: `haxelib run ceramic setup --cwd your/custom/path`

**--version {tag}**

During setup, ask for a specific release of ceramic identified by the given version tag.
Usage: `haxelib run ceramic setup --version v0.5.0` ([see available releases](https://github.com/ceramic-engine/ceramic/releases)).

**--install**

Run installation procedure without asking for confirmation.

**--global**

Make ceramic installation global without having to confirm it manually.

**--local**

Make ceramic installation local (not global) without having to confirm it manually.

## About ceramic

Get more info about ceramic [in its main repository](https://github.com/ceramic-engine/ceramic).
