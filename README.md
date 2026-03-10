# Cozy CLI Parser
[![License](https://img.shields.io/badge/license-GPLv2%2B-blue.svg)](LICENSE.md)

> Command-Line Parser Builder for Nim.

Cozy CLI Parser provides a thin convenience wrapper over `std/parseopt`.
It exports a `macro buildParser` which generates a command-line parser
from a set of regular, fully type-checked procedure calls and option-handling closures.

- A single place to declare options, flags and arguments — not
  three (parser, help text, shortNoVal/longNoVal set and seq).
- Low-magic implementation: no cryptic compiler errors.
- Same DIY stdlib approach: parsing only, handling is fully in your control.
- No idiosyncratic DSL: just regular Nim checked by the compiler.
- Declaration and handling code are co-located and cannot go out of sync.
- Slim code, no dependencies beyond `std/[parseopt, strutils, terminal, envvars]`.
- Colorized help strings.

## Documentation
The rendered API documentation and detailed guides are located in the `docs`
directory and should be available online at indiscipline.github.io/cozycliparser.

## Installation
Cozy CLI Parser is in the nimble directory, use `atlas` or `nimble` to install:

```bash
atlas use cozycliparser
```

```bash
nimble install cozycliparser
```

## Usage

Call `macro buildParser` with a program name, a help namespace name, a parser
mode, and a declarative body. The `opt`, `flag`, `arg` and `cmd` routines
register options, flags, positional arguments and subcommands along with their
handlers — closures passed as the last argument. The handlers are invoked when
the parser meets the corresponding input.

<!-- EXAMPLE_START -->
```nim
import cozycliparser

type Options = object
  output: string
  input: string
  verbose: bool
  greetName: string = "world"

var options: Options
buildParser(parseConfig(helpPrefix = "Greeter v0.1\nThis program greets."),
            "greeter", "Cli", GnuMode):
  opt('\0', "output", "Output file", "FILE") do (val: string):
    options.output = val
  flag('v', "verbose", "Enable verbose output") do ():
    options.verbose = true
  arg("INPUT", "Input file") do (val: string):
    options.input = val
  cmd("greet", "Greets NAME") do ():
    arg("NAME", "Name to greet") do (val: string):
      if val != "": options.greetName = val
      echo "Hello ", options.greetName
  cmd("version", "Displays version and quits") do ():
    run do ():
      quit("v0.42", 0)

# HelpText namespace is automatically built and injected in scope:
doAssert $Cli.help == """Greeter v0.1
This program greets.

Usage: greeter [options] INPUT <greet> <version>

Arguments:
  INPUT  Input file

Commands:
  greet    Greets NAME
  version  Displays version and quits

Options:
  --output=FILE  Output file
  -v, --verbose  Enable verbose output
  -h, --help     Show this help and exit"""

# Display colorized help for the program and subcommands with:
Cli.help.display()

Cli.greet.help.display()
```
<!-- EXAMPLE_END -->


*By default, a `-h`/`--help` flag is auto-injected at every parser level,
providing styled, nested help outputs natively.*

## TODO:

- [ ] Propose standard library inclusion, close [#12425](https://github.com/nim-lang/Nim/issues/12425).

## Contributing
The project is open for contributions.
Simplifying and reducing loc is preferable to expanding the featureset.

**Important:** In order to facilitate possible standard library inclusion,
all contributors must agree to the [Contributor License Agreement (CLA)](CLA.md).
This guarantees that the Maintainer has the right to
submit the Project's code for inclusion into the Nim language Standard Library.
While your contributions will be distributed under GPL-2.0-or-later for this
project, the CLA explicitly grants the Maintainer the right to relicense your
contribution under the **MIT License** solely for the purpose of proposing its
inclusion into the official Nim Standard Library.

## License
Cozy CLI Parser is licensed under GNU General Public License version 2.0 or later.
See `LICENSE` for full details.
