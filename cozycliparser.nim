# SPDX-FileCopyrightText: 2026 Kirill Ildyukov <elephanttalk+git {аt} protonmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

## cozycliparser: Command-Line Parser Builder
## ==========================================
##
## A thin but useful wrapper over `std/parseopt`.
##
## Features:
## - A single place to declare options, flags and arguments -
##   not three (parser, help text, shortNoVal/longNoVal set and seq).
## - Low-magic implementation: no cryptic compiler errors.
## - Same DIY stdlib approach: parsing only, handling is fully
##   in your control.
## - No idiosyncratic DSL: just regular Nim checked by the compiler.
## - Declaration and handling code are co-located and cannot go out of sync.
## - Multiple `buildParser` calls in one module are supported.
## - Slim code, no dependencies beyond `std/[parseopt, strutils, terminal, envvars]`.
##
## Provides `macro buildParser`_, which generates the command-line parser
## from a set of regular, fully type-checked procedure calls and
## option-handling closures.
##
## Quick start
## -----------
##
## Call `macro buildParser`_ with a program name, a help token name,
## a parser mode, and a declarative body. The `opt`_, `flag`_, `arg`_ and
## `cmd`_ routines register options, flags, positional arguments and
## subcommands along with their handlers - closures passed as the last
## argument. The handlers are invoked when the parser meets the corresponding
## input.
##
runnableExamples:
  type Options = object
    output: string
    input: string
    verbose: bool
    greetName: string = "world"

  var options: Options
  buildParser(parserConfig(helpPrefix = "Greeter v0.1\nThis program greets."),
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

  doAssert $Cli.help == """Greeter v0.1
This program greets.

Usage: greeter [options] INPUT <greet>

Arguments:
  INPUT  Input file

Commands:
  greet  Greets NAME

Options:
  --output=FILE  Output file
  -v, --verbose  Enable verbose output
  -h, --help     Show this help and exit"""

  doAssert $Cli.help("greet") == """Greeter v0.1
This program greets.

Usage: greeter greet [options] NAME

Arguments:
  NAME  Name to greet

Options:
  -h, --help  Show this help and exit"""

##
## .. Important::
##    By default (`ParserConfig.helpAuto = true`), a `-h`/`--help` flag is
##    auto-injected at every parser level, writing help to `stdout` and
##    calling `quit(0)`. Registering a flag that conflicts with the configured
##    short or long key at a given level suppresses that key or the whole
##    auto-injection (if both were shadowed) with a hint or a warning.
##
## `buildParser` injects a single name into the outer scope:
##
## - `const Cli`: a typed token. Access help as `Cli.help` (root level) or
##   `Cli.help("sub cmd")` (subcommand). Call `$Cli.help` for a plain string,
##   or `Cli.help.display(<fd>)` for styled output.
##
## Accessing help
## --------------
##
## After `buildParser`, help is available through the injected constant
## named by the `helpName` argument (`"Cli"` in the examples).
## Call `help`_ on it to get the root-level `HelpView`, or pass a
## subcommand path string to reach a nested level:
##
runnableExamples("-r:off"):
  buildParser("tool", "Cli", GnuMode):
    flag('v', "verbose", "Enable verbose output") do ():
      discard

  discard Cli.help              # root-level HelpView
  discard Cli.help("sub")       # subcommand HelpView (returns root's if unknown)
  discard Cli.help("remote add") # nested subcommand HelpView
  discard $Cli.help             # plain string
  Cli.help.display()            # styled output to stdout
  Cli.help.display(stderr)      # styled output to stderr
##
## .. note:: "bare" subcommands with only a `run`_ handler and no `arg`_,
##    `opt`_, or `flag`_ registrations do not receive a help entry.
##    Accessing their path via `Cli.help("path")` returns the help text
##    of their parent level.
##
## If you need to reference the token *before* `buildParser` runs -- for
## example, to define a helper proc that displays help and is called from
## inside a handler closure -- declare the token first with `setParser`_:
##
runnableExamples("-r:off"):
  setParser("Cli")

  # Cli is now in scope. Its help storage is empty until buildParser runs.
  proc showHelp() = Cli.help.display(stderr)

  buildParser("tool", Cli, GnuMode):
    arg("FILE", "Input file") do (val: string):
      if val.len == 0:
        showHelp(); quit(1)
##
## When using `setParser`_ explicitly, pass the token directly to
## `buildParser` -- do not pass the string name, as that would call
## `setParser`_ a second time and redeclare the token.
##
## Help string interpolation
## +++++++++++++++++++++++++
##
## Because help text is built at compile time, injecting dynamic runtime
## values (like the current directory or an environment variable) into help
## descriptions is done via a lazy interpolation (string replacement) hook.
##
## Register an interpolator on the token using `setHelpInterpolator`_.
## The closure is invoked exactly when the help text is converted to a
## string (`$`) or displayed.
##
## Only plain-text help spans (the optional `helpPrefix` and description
## paragraphs) are passed through the interpolator. Left-column syntax
## (keys, arg names, metavars, section names) is not interpolated.
##
## .. warning:: Adding new lines to the interpolated strings will break
##    formatting!
##
runnableExamples:
  import std/strutils

  buildParser(parserConfig(helpPrefix = "MyProg $ver"), "myprog", "Cli", GnuMode):
    opt('d', "dir", "Target directory (default: $dir)", "PATH") do (_: string):
      discard

  let currentDir = "/tmp" # simulates os.getCurrentDir()

  Cli.setHelpInterpolator:
    s.multiReplace(
      ("$ver", "v1.2.3"),
      ("$dir", currentDir)
    )

  doAssert $Cli.help == """
MyProg v1.2.3

Usage: myprog [options]

Options:
  -d, --dir=PATH  Target directory (default: /tmp)
  -h, --help      Show this help and exit"""
##
## The registered interpolator fires once per plain-text span, so calls
## inside it are evaluated repeatedly. Precompute and cache any expensive
## values in variables before the closure captures them.
##
## Optional short / long forms
## ---------------------------
##
## - Pass `'\0'` (or any char with `ord < 32`) as `short` to suppress the
##   short form of an option or flag.
## - Pass `""` as `name` to suppress the long form.
##
## Attempting to suppress both is a compile-time error.
##
## Subcommands
## -----------
##
## Declare subcommands with `cmd`. Register the subcommand's own options
## directly inside the cmd's closure:
##
runnableExamples("-r:off"):
  type Options = object
    addQueue: seq[string]
    force: bool

  var options: Options
  buildParser("git", "Cli", GnuMode):
    cmd("add", "Add files to the index") do ():
      arg("FILE", "File to add") do (val: string):
        if val != "": options.addQueue.add(val)
      flag('f', "force", "Add anything") do ():
        options.force = true
##
## Nesting is supported.
##
## When a subcommand fires, there are two approaches to acting on it:
##
## **1. `run` handler**
##
## Register a command-handling hook with `run`_. It is called once right
## after that subcommand's parser loop finishes.
##
runnableExamples("-r:off"):
  type Options = object
    filterCol, filterRe: string

  var options: Options
  buildParser("csvtool", "Cli", GnuMode):
    cmd("filter", "Filter rows by column value") do ():
      arg("COLUMN", "Column name") do (val: string):
        options.filterCol = val
      opt('r', "regex", "Match pattern", "RE") do (val: string):
        options.filterRe = val
      run do ():
        discard # act on `options`, call other procs, etc.
    cmd("version", "Prints version and exits") do ():
      run do ():
        quit("csvtool v0.1", 0)
##
## Only one `run` handler is allowed per parser level.
## A `run` handler registered at the root level is called after the main
## parser loop finishes.
##
## **2. Global state**
##
## Track which subcommand was selected in a state variable and act on
## it after `buildParser` returns.
##
runnableExamples():
  type
    Cmd = enum cmdNone, cmdFilter
    Options = object
      cmd: Cmd
      filterCol, filterRe: string

  var options = Options()
  buildParser("csvtool", "Cli", GnuMode):
    cmd("filter", "Filter rows by column value") do ():
      arg("COLUMN", "Column name") do (val: string):
        options.filterCol = val
        options.cmd = cmdFilter
      opt('r', "regex", "Match pattern", "RE") do (val: string):
        options.filterRe = val

  case options.cmd
  of cmdFilter:
    echo options
  of cmdNone:
    discard # Cli.help.display(); quit(1) # goes here
##
## Default values
## --------------
##
## No built-in support for default option values is provided.
## Nim's [default values for object fields](https://nim-lang.org/docs/manual.html#types-default-values-for-object-fields)
## enable this convenient pattern:
##
runnableExamples:
  from std/strutils import parseInt

  const
    DefWidth  = 2
    DefHeight = 21

  type Options = object
    width:  int = DefWidth
    height: int = DefHeight

  proc validateNum(s: string): Natural =
    try:
      let i = parseInt(s)
      if i notin 0..100:
        raise newException(ValueError, "Value not in range [0..100]: " & $i)
    except ValueError as e: quit("Error: " & e.msg, 1)

  var options = Options()
  buildParser("multiplier", "Cli", NimMode):
    opt('w', "width",  "Width value. Default=" & $DefWidth,  "W") do (n: string):
      options.width = validateNum(n)
    opt('h', "height", "Height value. Default=" & $DefHeight, "H") do (n: string):
      # `h` shadows the short key for auto-injected help; a hint will be shown.
      options.height = validateNum(n)

  doAssert options.width * options.height == 42
##
## Error handling
## --------------
##
## Unknown options are routed to the installed error handler. The default
## handler writes the offending option and the relevant help text to `stderr`,
## then exits with code `1`.
##
## Override it with `proc onError`_:
##
runnableExamples("-r:off"):
  buildParser("myprog", "Cli", GnuMode):
    flag('v', "verbose", "Enable verbose output") do ():
      discard

  Cli.onError do (e: ParseError):
    stderr.writeLine "Unknown option: ", e.key
    e.help.display(stderr)
    quit(1)
##
## `ParseError` fields:
## - `key`: option/argument name as seen on the command line (no leading dashes).
## - `val`: associated value, or `""` for flags and bare unknowns.
## - `path`: active subcommand chain, e.g. `""` at root or `"remote add"`.
## - `help`: `HelpText` for the active parser level.
##
## There is one `onError` handler per parser; `e.path` and `e.help`
## distinguish which level triggered the error.
##
## Principle of operation
## ----------------------
##
## `buildParser` does the following:
##
## 1. Walks the body AST recursively, following cmd closure nesting, collecting
##    opt/flag/arg/run/cmd metadata into a Scope tree.
## 2. Emits one `const <sym>: HelpText` per parser level (compile-time constant).
## 3. Populates the per-token storage's helpMap at runtime so `tok.help(path)`
##    can dispatch to the right HelpText by path string.
## 4. Resets the active registration context, executes the body (registering
##    handlers), then commits the context into permanent per-token storage.
## 5. Installs the default error handler.
## 6. Emits `<subcmd>Cmd` procs (innermost first), each with its own
##    `initOptParser` + `getopt` loop and run handler.
## 7. Emits the root-level loop.
##
## Per-token storage is keyed on a unique phantom type gensym'd by `setParser`.
## Two modules both using `"Cli"` produce tokens with distinct phantom types
## and therefore distinct storage instantiations, so they never collide.

import std/[macros, parseopt, strutils, terminal]
from std/envvars import getEnv
export CliMode, ForegroundColor, Style
export remainingArgs

type
  HelpTag* = enum
    ## Semantic tags applied to help text spans for styling purposes.
    ## `htPlain` spans are passed through the interpolator; all others are not.
    htPlain    ## whitespace, punctuation, "[options]" - never styled
    htProgName ## program name in the usage line
    htSection  ## "Usage:", "Arguments:", "Commands:", "Options:"
    htArg      ## positional name/metavar in listings and usage
    htMetavar  ## value placeholder after an opt key: "FILE", "CHAR"
    htShortKey ## short option form: "-v", "-s"
    htLongKey  ## long option form: "--verbose", "--output"
    htSubCmd   ## subcommand name in command listing

  HelpSpan* = object
    text*: string
    tag*: HelpTag

  HelpText* = seq[HelpSpan]
  ## A sequence of tagged text spans that together form one help page.
  ## `$` on a bare `HelpText` concatenates span text without interpolation;
  ## use `HelpView` (returned by `help`_) for interpolator-aware conversion.

  HelpPalette* = array[HelpTag, tuple[fg: ForegroundColor, style: set[Style]]]

const DefaultPalette*: HelpPalette = [
  htPlain:    (fgDefault, {}),
  htProgName: (fgDefault, {}),
  htSection:  (fgYellow, {styleDim}),
  htArg:      (fgCyan, {styleBright}),
  htMetavar:  (fgCyan, {}),
  htShortKey: (fgGreen, {styleBright}),
  htLongKey:  (fgBlue, {styleBright}),
  htSubCmd:   (fgMagenta, {styleBright})
]

type
  OutStream* = enum
    ## Output stream selector for use in `ParserConfig`_ fields.
    osStdout = "stdout"
    osStderr = "stderr"

  ParserConfig* = object
    ## Compile-time configuration for `macro buildParser`_.
    ## Use `parserConfig`_ proc to selectively override the defaults.
    helpPrefix*: string = ""   ## A header prepended to all help strings
    helpAuto*: bool = true   ## inject -h/--help at every level unless overridden
    helpFlag*: (char, string) = ('h', "help")
    helpText*: string = "Show this help and exit"
    helpStream*: OutStream = osStdout
    helpExitCode*: int = 0
    useColors*: bool = true
    errorExitCode*: int = 1
    errorShowHelp*: bool = true   ## display help on unknown input
    errorStream*: OutStream = osStderr
    fmtIndent*: int = 2
    fmtColSep*: int = 2       ## minimal help text alignment shift
    palette*: HelpPalette = DefaultPalette
    debug*: bool = false  ## print the expanded macro AST at compile time

macro emitParserConfigConstructor(): untyped =
  let
    recList = bindSym("ParserConfig").getImpl[2][2]
    formalParams = nnkFormalParams.newTree(ident("ParserConfig"))
    objConstr = nnkObjConstr.newTree(ident("ParserConfig"))
  for def in recList:
    if def.kind != nnkIdentDefs: continue
    let fieldName = if def[0].kind == nnkPostfix: def[0][1] else: def[0]
    let fieldType = def[1]
    var fieldDef = if def[2].kind == nnkHiddenSubConv: def[2][1] else: def[2]
    if fieldDef.kind == nnkIntLit:
      let impl = fieldType.getImpl
      if impl != nil and impl.kind == nnkEnumTy:
        for member in impl:
          if member.kind == nnkSym and member.intVal == fieldDef.intVal:
            fieldDef = ident($member); break
      elif $fieldType == "bool":
        fieldDef = ident($bool(fieldDef.intVal))
    formalParams.add nnkIdentDefs.newTree(fieldName, newEmptyNode(), fieldDef)
    objConstr.add nnkExprColonExpr.newTree(fieldName, fieldName)
  result = nnkProcDef.newTree(
    nnkPostfix.newTree(ident("*"), ident("parserConfig")),
    newEmptyNode(), newEmptyNode(),
    formalParams,
    nnkPragma.newTree(ident("compiletime")),
    newEmptyNode(),
    nnkStmtList.newTree(objConstr))

emitParserConfigConstructor()

type CliHelp*[Tag: static string; Id] = object
  ## Phantom token minted once per `setParser`_ call.
  ## `Tag` is the user-visible name; `Id` is a unique gensym'd type that
  ## isolates per-call storage so same-named tokens from different modules
  ## never collide.

type
  OptKind = enum
    okOpt   ## --key=val / -k val
    okFlag  ## --flag / -f, no value
    okArg   ## positional argument
    okRun   ## post-loop hook

  OptHandler*    = proc (val: string) {.closure.}
  FlagHandler*   = proc () {.closure.}
  ArgHandler*    = proc (key: string) {.closure.}
  CmdRunHandler* = proc () {.closure.}

  Handler* = object
    case kind*: OptKind
    of okOpt: onOpt*: OptHandler
    of okFlag: onFlag*: FlagHandler
    of okArg: onArg*: ArgHandler
    of okRun: onRun*: CmdRunHandler

  ParseError* = object
    ## Describes an unknown option or argument encountered during parsing.
    key*: string  ## option name as seen on the command line (no leading dashes)
    val*: string  ## associated value, or `""` for flags and bare unknowns
    path*: string  ## active subcommand chain, e.g. `""` at root or `"remote add"`
    help*: HelpText ## help page for the active parser level

  ErrorHandler* = proc (e: ParseError) {.closure.}

  BpContext = object
    handlers: seq[Handler]
    onError: ErrorHandler
    interpolator: proc (s: string): string
    helpLookup: proc (path: string): HelpText

proc bpStorage[Tag: static string; Id](
    _: CliHelp[Tag, Id]): var BpContext =
  ## Returns the permanent per-call `BpContext` for this token.
  ## Each unique `Id` type gets its own `{.global.}` instance.
  var store {.global.}: BpContext
  store

type HelpView*[Tag: static string; Id] = object
  ## A `HelpText` bound to a specific parser token.
  ## `$` and `display`_ on a `HelpView` automatically apply the interpolator
  ## registered on the same token, unlike calling them on a bare `HelpText`.
  doc*: HelpText

template help*[Tag: static string; Id](
    token: CliHelp[Tag, Id]; path: string = ""): HelpView[Tag, Id] =
  ## Returns the `HelpView` for `path` (`""` = root level).
  ## If `path` is not found, returns the root help page.
  ## The view carries the token identity so `$` and `display`_ apply the
  ## registered interpolator automatically.
  HelpView[Tag, Id](doc: bpStorage(token).helpLookup(path))

var bpActive* {.threadvar.}: BpContext
  ## Scratch context written by registration procs during `buildParser` body
  ## execution. Committed into `bpStorage` by the macro after the body runs.

proc opt*(short: char; name, help, metavar: string; handler: OptHandler) =
  ## Registers a key-value option (`--name=val` / `-s val`).
  ## Pass `'\0'` for `short` to omit the short form; `""` for `name` to omit
  ## the long form. `metavar` is the value placeholder in usage lines.
  bpActive.handlers.add Handler(kind: okOpt, onOpt: handler)

template optreg*(short: char; name, help, metavar: string; body: untyped) =
  ## Convenience wrapper for `opt`_. Injects `val` for the parsed value.
  opt(short, name, help, metavar, proc(val {.inject.}: string) = body)

proc flag*(short: char; name, help: string; handler: FlagHandler) =
  ## Registers a boolean flag (`--name` / `-s`), fired with no value.
  ##
  ## Pass `'\0'` for `short` to omit the short form; `""` for `name` to omit
  ## the long form.
  bpActive.handlers.add Handler(kind: okFlag, onFlag: handler)

template flagreg*(short: char; name, help: string; body: untyped) =
  ## Convenience wrapper for `flag`_.
  flag(short, name, help, proc() = body)

proc arg*(name, help: string; handler: ArgHandler) =
  ## Registers a positional argument handler. Multiple `arg` calls are allowed
  ## per parser level. Tokens are dispatched in registration order; the last
  ## handler absorbs overflow.
  bpActive.handlers.add Handler(kind: okArg, onArg: handler)

template argreg*(name, help: string; body: untyped) =
  ## Convenience wrapper for `arg`_. Injects `key` for the parsed argument.
  arg(name, help, proc(key {.inject.}: string) = body)

proc run*(handler: CmdRunHandler) =
  ## Registers a closure called once after this parser level's loop finishes.
  ## Use it to perform actions in a command's own context immediately after
  ## its arguments have been parsed, without tracking state externally.
  ##
  ## Only one `run` handler is allowed per parser level.
  bpActive.handlers.add Handler(kind: okRun, onRun: handler)

template runreg*(body: untyped) =
  ## Convenience wrapper for `run`_.
  run(proc() = body)

proc cmd*(name, help: string; cmdRegistrations: proc()) =
  ## Declares a subcommand. `cmdRegistrations` is called immediately to
  ## register the subcommand's own options, flags, args and nested commands,
  ## not when the command is met during parsing.
  ##
  ## This, conceptually, declares a parsing level, not a command
  ## handler.
  ##
  ## To act on a command during parsing, use `proc run`_.
  ## Use `arg`_, `flag`_, `opt`_, `run`_ or `cmd` itself inside
  ## `cmdRegistrations`, as you do at the root parser level.
  #
  # At runtime, when the token `name` is encountered, `cmd` delegates parsing
  # to the generated `<name>Cmd(remainingArgs)` proc with its own parser loop.
  cmdRegistrations()

template command*(name, help: string; body: untyped) =
  ## Convenience wrapper for `cmd`_.
  cmd(name, help, proc() = body)

proc onError*[Tag: static string; Id](
    token: CliHelp[Tag, Id]; handler: ErrorHandler) =
  ## Installs a custom unknown-option handler. One handler serves all parser
  ## levels. Inspect `e.path` and `e.help` to distinguish the level.
  ##
  ## The default handler writes the unknown option and the relevant help text
  ## to `stderr`, then exits with code 1.
  bpStorage(token).onError = handler

proc helpInterpolator*[Tag: static string; Id](
    token: CliHelp[Tag, Id]; handler: proc(s: string): string) =
  ## Installs a custom interpolator for help text descriptions and prefixes.
  ## Evaluated lazily when help text is converted to string or displayed.
  bpStorage(token).interpolator = handler

template setHelpInterpolator*[Tag: static string; Id](
    token: CliHelp[Tag, Id]; body: untyped) =
  ## Convenience wrapper for `helpInterpolator`_.
  ## Injects `s` for the closure's string parameter.
  helpInterpolator(token, proc(s {.inject.}: string): string = body)

proc canStyle(f: File): bool =
  if getEnv("NO_COLOR").len > 0: return false
  let force = getEnv("CLICOLOR_FORCE")
  if force == "1" or force == "true": return true
  isatty(f)

proc resolve(span: HelpSpan; interp: proc(s: string): string): string {.inline.} =
  if interp != nil and span.tag == htPlain: interp(span.text)
  else: span.text

proc write*(f: File; doc: HelpText;
            interp: proc(s: string): string = nil) =
  for span in doc: f.write(span.resolve(interp))

proc `$`*(doc: HelpText): string =
  ## Converts `doc` to a plain string by concatenating all span text.
  ## The registered interpolator is NOT applied; use `$` on a `HelpView`_
  ## (returned by `help`_) to get interpolated output.
  for span in doc: result.add span.text

proc display*(doc: HelpText; f: File = stdout; palette = DefaultPalette;
              interp: proc(s: string): string = nil) =
  ## Writes `doc` styled if the terminal supports it, plain otherwise.
  ## Respects `NO_COLOR` and `CLICOLOR_FORCE`.
  if not canStyle(f):
    f.write(doc, interp)
  else:
    for span in doc:
      let text = span.resolve(interp)
      let (fg, style) = palette[span.tag]
      if fg == fgDefault and style == {}:
        f.write(text)
      else:
        f.styledWrite(style, fg, text)
  f.write('\n')

proc display[Tag: static string; Id](
    doc: HelpText; token: CliHelp[Tag, Id];
    palette = DefaultPalette; f: File = stdout) =
  ## Token-aware overload used by macro-generated -h/--help and error
  ## call sites, which hold a bare `HelpText` const and the token separately.
  display(doc, f, palette, bpStorage(token).interpolator)

proc `$`*[Tag: static string; Id](v: HelpView[Tag, Id]): string =
  ## Converts `v` to a plain string, applying the registered interpolator.
  let interp = bpStorage(CliHelp[Tag, Id]()).interpolator
  for span in v.doc: result.add span.resolve(interp)

proc display*[Tag: static string; Id](
    v: HelpView[Tag, Id]; f: File = stdout; palette = DefaultPalette) =
  ## Displays `v` styled (or plain), applying the registered interpolator.
  display(v.doc, f, palette, bpStorage(CliHelp[Tag, Id]()).interpolator)

type
  OptSpec = object
    ## Compile-time metadata for one registration call.
    kind: OptKind
    short: char
    name: string
    help: string
    metavar: string
    absIdx: int  ## absolute index into bpCtx.handlers; set during extractScope

  CmdSpec = object
    name: string
    help: string
    scope: Scope

  Scope = ref object
    ## Compile-time metadata for one parser level (root or subcommand).
    progName: string
    path: string  ## joined subcommand chain, e.g. "" at root or "remote add"
    specs: seq[OptSpec]
    cmds: seq[CmdSpec]
    autoHelp: OptSpec
    argIdxs: seq[int]
    runIdx: int = -1
    bareRun: bool  ## no opts/flags/args and at most one run handler; set by extractScope
    helpSym: NimNode  ## gensym'd const holding this scope's HelpText; set by buildHelpConsts

template keyOk(c: char): bool = c.ord >= 32
template keyOk(s: openArray[char]): bool = s.len > 0
template hasShort(s: OptSpec): bool = s.short.keyOk()
template hasLong(s: OptSpec): bool = s.name.keyOk()

proc addSpan(doc: var HelpText; tag: HelpTag; a: varargs[string]) =
  if a.len == 0: return
  if doc.len > 0 and doc[^1].tag == tag:
    for p in a: doc[^1].text.add p
  else:
    doc.add HelpSpan(tag: tag)
    for p in a: doc[^1].text.add p

template plain(doc: var HelpText; text: varargs[string]) =
  doc.addSpan(htPlain, text)

func specEntry(s: OptSpec): tuple[spans: HelpText, width: int] =
  if s.hasShort:
    result.spans.addSpan(htShortKey, "-", $s.short)
    result.width.inc 2
    if s.hasLong:
      result.spans.plain(", ")
      result.width.inc 2
  if s.hasLong:
    result.spans.addSpan(htLongKey, "--", s.name)
    result.width.inc 2 + s.name.len
    if s.kind == okOpt:
      result.spans.plain("=")
      result.spans.addSpan(htMetavar, s.metavar)
      result.width.inc 1 + s.metavar.len

func generateHelp(prefix, progName: string; specs: openArray[OptSpec];
                  cmds: openArray[CmdSpec]; autoHelp: OptSpec;
                  indent, colSep: int): HelpText =
  type Row = object
    spans: HelpText ## pre-built left-column spans (opts) or empty (arg/cmd)
    name: string    ## plain name for arg and cmd rows
    help: string
    colWidth: int

  var argRows, cmdRows, optRows: seq[Row]
  var maxArg, maxCmd, maxOpt = 0

  for spec in specs:
    case spec.kind
    of okArg:
      maxArg = max(maxArg, spec.name.len)
      argRows.add Row(name: spec.name, help: spec.help, colWidth: spec.name.len)
    of okOpt, okFlag:
      let (spans, w) = specEntry(spec)
      maxOpt = max(maxOpt, w)
      optRows.add Row(spans: spans, help: spec.help, colWidth: w)
    of okRun: discard

  if autoHelp.kind == okFlag:
    let (spans, w) = specEntry(autoHelp)
    maxOpt = max(maxOpt, w)
    optRows.add Row(spans: spans, help: autoHelp.help, colWidth: w)

  for c in cmds:
    maxCmd = max(maxCmd, c.name.len)
    cmdRows.add Row(name: c.name, help: c.help, colWidth: c.name.len)

  let pad = spaces(indent)
  let sep = spaces(colSep)

  if prefix.len > 0: result.plain(prefix, "\n\n")

  result.addSpan(htSection, "Usage:")
  result.plain(" ")
  result.addSpan(htProgName, progName)
  if optRows.len > 0: result.plain(" [options]")
  for r in argRows:
    result.plain(" ")
    result.addSpan(htArg, r.name)
  for c in cmds:
    result.plain(" <")
    result.addSpan(htSubCmd, c.name)
    result.plain(">")

  proc section(d: var HelpText; label: string; rows: seq[Row];
               maxWidth: int; tag: HelpTag) =
    if rows.len == 0: return
    d.plain("\n\n")
    d.addSpan(htSection, label, ":")
    let helpIndent = spaces(indent + maxWidth + colSep)
    for r in rows:
      d.plain("\n", pad)
      case tag
      of htLongKey: d.add r.spans
      of htSubCmd: d.addSpan(htSubCmd, r.name)
      else: d.addSpan(htArg, r.name)
      d.plain(spaces(maxWidth - r.colWidth), sep)
      let lines = r.help.splitLines()
      d.plain(lines[0])
      for i in 1..high(lines): d.plain("\n", helpIndent, lines[i])

  result.section("Arguments", argRows, maxArg, htArg)
  result.section("Commands",  cmdRows, maxCmd, htSubCmd)
  result.section("Options",   optRows, maxOpt, htLongKey)

func generateHelp(s: Scope; cfg: ParserConfig): HelpText =
  let name = if s.path.len > 0: s.progName & " " & s.path else: s.progName
  generateHelp(cfg.helpPrefix, name, s.specs, s.cmds, s.autoHelp,
               cfg.fmtIndent, cfg.fmtColSep)

proc injectAutoHelp(scope: Scope; cfg: ParserConfig;
                    shortOverridden, longOverridden: bool;
                    conflictNode: NimNode) =
  let (hShort, hLong) = cfg.helpFlag
  let allOverridden = (not keyOk(hShort) or shortOverridden) and
                      (not keyOk(hLong)  or longOverridden)
  if allOverridden:
    warning("buildParser: all help keys shadowed; auto-help suppressed.", conflictNode)
    return
  if shortOverridden:
    hint("buildParser: short help key '-" & $hShort & "' shadowed.", conflictNode)
  elif longOverridden:
    hint("buildParser: long help key '--" & hLong & "' shadowed.", conflictNode)
  scope.autoHelp = OptSpec(kind: okFlag,
                           short: if shortOverridden: '\0' else: hShort,
                           name: if longOverridden: ""   else: hLong,
                           help: cfg.helpText)

proc extractScope(progName: string; body: NimNode; cfg: ParserConfig;
                  path: string; baseIdx: int): tuple[s: Scope, next: int] =
  var scope = Scope(progName: progName, path: path)
  var next = 0

  var stmts: seq[NimNode]
  for s in body:
    if s.kind == nnkStmtList:
      for inner in s: stmts.add inner
    else: stmts.add s

  let (hShort, hLong) = cfg.helpFlag
  var shortOverridden, longOverridden = false
  var conflictNode: NimNode

  for stmt in stmts:
    if stmt.kind in {nnkCommentStmt, nnkEmpty, nnkMixinStmt}: continue
    if stmt.kind notin {nnkCall, nnkCommand}:
      error("buildParser: only opt, flag, arg, run, cmd calls are allowed " &
            "in the parser body", stmt)
    let callee = $stmt[0]
    case callee
    of "opt", "flag":
      let isOpt = callee == "opt"
      let spec = OptSpec(
        kind: if isOpt: okOpt else: okFlag,
        short: chr(stmt[1].intVal.uint8),
        name: stmt[2].strVal,
        help: stmt[3].strVal,
        metavar: if isOpt: stmt[4].strVal else: "",
        absIdx: baseIdx + next)
      if not spec.hasShort and not spec.hasLong:
        error(callee & ": must have at least one of short or long form", stmt)
      if cfg.helpAuto:
        if spec.hasShort and keyOk(hShort) and spec.short == hShort:
          shortOverridden = true
          if conflictNode == nil: conflictNode = stmt
        if spec.hasLong and keyOk(hLong) and spec.name == hLong:
          longOverridden = true
          if conflictNode == nil: conflictNode = stmt
      scope.specs.add spec
      inc next
    of "arg":
      let absIdx = baseIdx + next
      scope.argIdxs.add absIdx
      scope.specs.add OptSpec(kind: okArg, name: stmt[1].strVal,
                              help: stmt[2].strVal, absIdx: absIdx)
      inc next
    of "run":
      if scope.runIdx >= 0:
        error("run: only one `run` handler allowed per parser level", stmt)
      scope.runIdx = baseIdx + next
      scope.specs.add OptSpec(kind: okRun, absIdx: baseIdx + next)
      inc next
    of "cmd":
      let
        name = stmt[1].strVal
        cmdHelp = stmt[2].strVal
        rawClosure = stmt[^1]
        lambdaNode =
          case rawClosure.kind
          of nnkHiddenStdConv: rawClosure[^1]
          of nnkLambda, nnkProcDef: rawClosure
          else: rawClosure
      let (childScope, childSize) =
        extractScope(progName, lambdaNode[^1], cfg,
                     (if path.len > 0: path & " " & name else: name), baseIdx + next)
      next.inc childSize
      scope.cmds.add CmdSpec(name: name, help: cmdHelp, scope: childScope)
    else:
      error("buildParser: unexpected call '" & callee & "' - only opt, " &
            "flag, arg, run and cmd are allowed in the parser body", stmt)

  scope.bareRun = scope.cmds.len == 0 and scope.argIdxs.len == 0 and
    scope.specs.len == (if scope.runIdx >= 0: 1 else: 0)
  if cfg.helpAuto:
    scope.injectAutoHelp(cfg, shortOverridden, longOverridden, conflictNode)
  (scope, next)

proc buildHelpConsts(scope: Scope; cfg: ParserConfig; fallback: NimNode = nil): NimNode =
  ## Emits one `const <sym>: HelpText = <literal>` per scope level.
  ## Sets `scope.helpSym` (and recursively each sub-scope's) as a side-effect.
  ## Bare-run scopes emit no const but inherit their parent's sym via `fallback`.
  result = newStmtList()
  if scope.bareRun:
    scope.helpSym = fallback
    return
  let sym = genSym(nskConst,
    (if scope.path.len == 0: "root"
     else: scope.path[scope.path.rfind(' ') + 1 .. ^1]) & "Help")
  scope.helpSym = sym
  let docNode = newLit(generateHelp(scope, cfg))
  result.add quote do:
    const `sym`: HelpText = `docNode`
  for c in scope.cmds:
    result.add buildHelpConsts(c.scope, cfg, sym)

proc buildHelpLookupInit(scope: Scope; token: NimNode): NimNode =
  ## Emits a single assignment installing a `case`-dispatching proc into
  ## `bpStorage(token).helpLookup`. Walks the scope tree to collect entries.
  ## Unknown paths fall through to the root scope's helpSym.
  let path = ident("path")
  let caseStmt = nnkCaseStmt.newTree(path)

  proc addEntries(s: Scope) =
    if s.bareRun: return
    let pathLit = newLit(s.path)
    caseStmt.add nnkOfBranch.newTree(pathLit, s.helpSym)
    for c in s.cmds:
      addEntries(c.scope)

  addEntries(scope)
  caseStmt.add nnkElse.newTree(scope.helpSym)

  let procExpr = quote do:
    proc(`path`: string): HelpText = `caseStmt`
  result = quote do:
    bpStorage(`token`).helpLookup = `procExpr`

proc helpDisplayCall(helpExpr, tokNode, palSym, stream: NimNode;
                     useColors: bool): NimNode =
  if useColors:
    newCall(bindSym"display", helpExpr, tokNode, palSym, stream)
  else:
    newCall(newDotExpr(stream, ident"write"), helpExpr)

type BCtx = object
  ## Bundles the parameters shared by `buildParserLoop` and `generateDispatchers`.
  ## Created once in `macro buildParser` and threaded through both procs.
  mode: CliMode
  ctxExpr: NimNode
  tokNode: NimNode
  palSym: NimNode
  cfg: ParserConfig

proc buildParserLoop(scope: Scope; bx: BCtx;
                     cmdlineNode: NimNode): tuple[setup, runCall: NimNode] =
  # Unpack bx into locals so that quote do: backtick interpolations get clean
  # symbol references rather than lifting the whole struct as a value literal.
  let
    ctxExpr = bx.ctxExpr
    tokNode = bx.tokNode
    palSym = bx.palSym
    mode = bx.mode
    cfg = bx.cfg
    parser = genSym(nskVar, "parser")
    key = ident("key")
    val = ident("val")
    kind = ident("kind")
    pathLit = newLit(scope.path)

  let helpSym = scope.helpSym

  var shortNoVal: set[char]
  var longNoVal: seq[string]

  let onError = quote do:
    `ctxExpr`.onError(ParseError(key: `key`, val: `val`,
                                 path: `pathLit`, help: `helpSym`))

  let keyCase = nnkCaseStmt.newTree(key)

  for spec in scope.specs:
    if spec.kind notin {okOpt, okFlag}: continue
    let idx = newLit(spec.absIdx)
    let branch = nnkOfBranch.newTree()
    if spec.hasShort: branch.add newLit($spec.short)
    if spec.hasLong: branch.add newLit(spec.name)
    if spec.kind == okFlag:
      if spec.hasShort: shortNoVal.incl spec.short
      if spec.hasLong: longNoVal.add spec.name
      branch.add quote do:
        `ctxExpr`.handlers[`idx`].onFlag()
    else:
      branch.add quote do:
        `ctxExpr`.handlers[`idx`].onOpt(`val`)
    keyCase.add branch

  if scope.autoHelp.kind == okFlag:
    let
      ah = scope.autoHelp
      stream = ident($cfg.helpStream)
      exitCode = newLit(cfg.helpExitCode)
      branch = nnkOfBranch.newTree()
    if ah.hasShort:
      shortNoVal.incl ah.short
      branch.add newLit($ah.short)
    if ah.hasLong:
      longNoVal.add ah.name
      branch.add newLit(ah.name)
    let helpAction = helpDisplayCall(helpSym, tokNode, palSym, stream, cfg.useColors)
    branch.add quote do: `helpAction`; quit(`exitCode`)
    keyCase.add branch

  keyCase.add nnkElse.newTree(onError)

  let argPos = ident("argPos")
  let argBody =
    if scope.argIdxs.len > 0:
      let idxArr = nnkBracket.newTree()
      for i in scope.argIdxs: idxArr.add newLit(i)
      let high = scope.argIdxs.high
      quote do:
        `ctxExpr`.handlers[`idxArr`[min(`argPos`, `high`)]].onArg(`key`)
        inc `argPos`
    else:
      onError

  let cmdArgBody =
    if scope.cmds.len > 0:
      let cmdCase = nnkCaseStmt.newTree(key)
      for c in scope.cmds:
        let procId = ident(c.name & "Cmd")
        let cmdName = newLit(c.name)
        let callNode = newCall(procId,
          newCall(newDotExpr(parser, bindSym"remainingArgs")))
        let branchBody = nnkStmtList.newTree(callNode, nnkBreakStmt.newTree(newEmptyNode()))
        cmdCase.add nnkOfBranch.newTree(cmdName, branchBody)
      cmdCase.add nnkElse.newTree(argBody)
      cmdCase
    else:
      argBody

  let snv = newLit(shortNoVal)
  let lnv = newLit(longNoVal)
  let initCall =
    if cmdlineNode.kind != nnkEmpty:
      quote do:
        initOptParser(`cmdlineNode`, shortNoVal=`snv`, longNoVal=`lnv`, mode=`mode`)
    else:
      quote do:
        initOptParser(shortNoVal=`snv`, longNoVal=`lnv`, mode=`mode`)

  let getoptLoop = quote do:
    for `kind`, `key`, `val` in `parser`.getopt():
      case `kind`
      of cmdEnd: discard
      of cmdArgument: `cmdArgBody`
      of cmdLongOption, cmdShortOption: `keyCase`

  result.setup = newStmtList(quote do: (var `parser` = `initCall`))
  if scope.argIdxs.len > 0:
    result.setup.add quote do:
      var `argPos` = 0
  result.setup.add getoptLoop

  result.runCall =
    if scope.runIdx >= 0:
      let ridx = newLit(scope.runIdx)
      quote do:
        if `ctxExpr`.handlers[`ridx`].onRun != nil:
          `ctxExpr`.handlers[`ridx`].onRun()
    else:
      newEmptyNode()

proc generateDispatchers(scope: Scope; bx: BCtx): NimNode =
  result = newStmtList()
  for c in scope.cmds:
    result.add generateDispatchers(c.scope, bx)
    let procId = ident(c.name & "Cmd")
    let args = ident("args")
    let (loopSetup, loopRunCall) = buildParserLoop(c.scope, bx, args)
    result.add quote do:
      proc `procId`(`args`: seq[string]) =
        if `args`.len > 0:
          `loopSetup`
        `loopRunCall`

macro setParser*(helpName: static string): untyped =
  ## Mints a unique phantom type for this parser call and injects
  ## `const <helpName>: CliHelp[<helpName>, <UniqueId>]` into the outer scope.
  ##
  ## The common case does not require calling `setParser` directly; the
  ## string-name `buildParser` overloads call it automatically. Use `setParser`
  ## explicitly only when you need to reference the token *before* `buildParser`
  ## runs - for example, to use inside functions that require help display
  ## and are called from inside the handler closures.
  ## After `setParser`, `helpName` is a valid symbol, but its help storage is
  ## empty until `buildParser` # populates it.
  ##
  ## Pass the `helpName` symbol directly to the token-taking `buildParser`
  ## overload, don't pass the string name again, as that would redeclare the symbol.
  let idType = genSym(nskType, "CliId")
  let tagLit = newLit(helpName)
  let helpId = ident(helpName)
  let errMsg = newLit(helpName & " is already declared in this scope; " &
                       "use a different name or remove the duplicate setParser call")
  result = quote do:
    when declared(`helpId`):
      {.error: `errMsg`.}
    type `idType` = object
    const `helpId` {.inject.} = CliHelp[`tagLit`, `idType`]()

macro buildParser*(cfg: static ParserConfig;
                   progName: static string;
                   token: CliHelp;
                   mode: static CliMode;
                   body: typed): untyped =
  ## Generates a complete CLI parser from a declarative body.
  ## `token` is the token injected by `setParser`_. Only `opt`_, `flag`_, `arg`_,
  ## `run`_ and `cmd`_ calls are allowed in `body`.
  var colorPreamble = newStmtList()
  let palSym = genSym(nskConst, "bpPalette")
  if cfg.useColors:
    let palNode = newLit(cfg.palette)
    colorPreamble = quote do:
      const `palSym`: HelpPalette = `palNode`

  let (topScope, _) = extractScope(progName, body, cfg, "", 0)

  let helpConsts = buildHelpConsts(topScope, cfg)
  let helpLookupInit = buildHelpLookupInit(topScope, token)

  let ctxExpr = quote do: bpStorage(`token`)
  let bx = BCtx(mode: mode, ctxExpr: ctxExpr,
                tokNode: token, palSym: palSym, cfg: cfg)

  let
    errStream = ident($cfg.errorStream)
    errExit = newLit(cfg.errorExitCode)
    eId = ident("e")
  let helpPrintCall = helpDisplayCall(topScope.helpSym, token, palSym, errStream, cfg.useColors)
  let showHelp = cfg.errorShowHelp
  let defaultOnError = quote do:
    bpStorage(`token`).onError = proc(`eId`: ParseError) =
      let prefix =
        if `eId`.val.len > 0: `eId`.key & "=" & `eId`.val else: `eId`.key
      let context =
        if `eId`.path.len > 0: `eId`.path & ": " else: ""
      `errStream`.writeLine("Error: ", context, "unknown option '", prefix, "'")
      when `showHelp`:
        `errStream`.write("\n")
        `helpPrintCall`
      quit(`errExit`)

  let dispatchers = generateDispatchers(topScope, bx)
  let (mainSetup, mainRunCall) = buildParserLoop(topScope, bx, newEmptyNode())

  result = quote do:
    `colorPreamble`
    `helpConsts`
    block:
      bpActive = BpContext()
      `body`
      bpStorage(`token`) = bpActive
      `helpLookupInit`
    `defaultOnError`
    `dispatchers`
    `mainSetup`
    `mainRunCall`

  if cfg.debug: hint("buildParser expansion:\n" & result.repr)

template buildParser*(progName: static string;
                      token: CliHelp;
                      mode: static CliMode;
                      body: typed): untyped =
  ## Convenience overload using the default `ParserConfig`.
  buildParser(ParserConfig(), progName, token, mode, body)

template buildParser*(cfg: static ParserConfig;
                      progName, helpName: static string;
                      mode: static CliMode;
                      body: typed): untyped =
  ## Unified single-call overload. Equivalent to `setParser(helpName)` +
  ## `buildParser(cfg, progName, <token>, mode, body)`.
  ## Injects `const <helpName>` into the outer scope.
  setParser(helpName)
  buildParser(cfg, progName, bindSym(helpName), mode, body)

template buildParser*(progName, helpName: static string;
                      mode: static CliMode;
                      body: typed): untyped =
  ## Convenience overload using the default `ParserConfig`.
  setParser(helpName)
  buildParser(ParserConfig(), progName, bindSym(helpName), mode, body)

when isMainModule:
  const
    HelpRoot = """Usage: csvtool [options] <filter> <version>

Commands:
  filter   Filter rows by column value
  version  Displays version and exits

Options:
  -s, --separator=CHAR  Field separator
  -c, --count=NUM       Number of rows to process
  --output=FILE         Output file
  -h, --help            Show this help and exit"""

    HelpFilter = """Usage: csvtool filter [options] COLUMN PATTERN

Arguments:
  COLUMN   Column name to match on
           Uses the provided pattern
  PATTERN  Value to match

Options:
  -h, --help  Show this help and exit"""

  type Options = object
    separator: string = ","
    output: string
    count: int
    filterCol: string
    filterRe: string

  var options = Options()

  setParser("Cli")

  doAssert bpStorage(Cli).handlers.len == 0
  proc showHelp() = Cli.help.display(stderr)

  buildParser(parserConfig(debug = true), "csvtool", Cli, NimMode):
    optreg('s', "separator", "Field separator", "CHAR"):
      options.separator = val
    opt('c', "count", "Number of rows to process", "NUM") do (val: string):
      try: options.count = val.parseInt
      except ValueError:
        quit("Error: count must be a number", 1)
    opt('\0', "output", "Output file", "FILE") do (val: string):
      options.output = val

    command("filter", "Filter rows by column value"):
      arg("COLUMN", "Column name to match on\nUses the provided pattern") do (val: string):
        options.filterCol = val
      argreg("PATTERN", "Value to match"):
        options.filterRe = key
      runreg:
        echo "filter done: col=", options.filterCol, " re=", options.filterRe

    cmd("version", "Displays version and exits") do ():
      runreg:
        echo "v0.1"

  doAssert $Cli.help == HelpRoot
  doAssert $Cli.help("filter") == HelpFilter
  showHelp()
