# ceramic (via haxelib)

Install ceramic via haxelib in current working directory:

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

Specify a custom working directory (can be used to install/update ceramic at a specific location). Usage: `haxelib run ceramic setup --cwd your/custom/path`

**--version {tag}**

During setup, ask for a specific release of ceramic idenfied by the given version tag. Usage: `haxelib run ceramic setup --version v0.5.0`. [See available release](https://github.com/ceramic-engine/ceramic/releases/tag/v0.5.0a)

## About ceramic

Get more info about ceramic [in its main repository](https://github.com/ceramic-engine/ceramic).
