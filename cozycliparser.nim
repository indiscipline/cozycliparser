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
## - Slim code, no dependencies beyond `std/[parseopt, strutils, terminal, envvars]`.
##
## Provides `macro buildParser`_, which generates the command-line parser
## from a set of regular, fully type-checked procedure calls and
## option-handling closures.
##
## Quick start
## -----------
##
## Call `macro buildParser`_ with a program name, a help namespace name,
## a parser mode, and a declarative body. The `opt`_, `flag`_, `arg`_ and
## `cmd`_ routines register options, flags, positional arguments and
## subcommands along with their handlers — closures
## passed as the last argument. The handlers are invoked when the parser
## meets the corresponding input.
##
runnableExamples:
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

  doAssert $Cli.greet.help == """Greeter v0.1
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
##    short or long form at a given level suppresses auto-injection there,
##    leaving full control to the user-provided handler.
##
## `buildParser` injects a single name into the outer scope:
##
## - `const Cli`: a zero-runtime-cost namespace of structured `HelpText`
##    values. Access as `Cli.help` (root) or `Cli.<subcmd>.help`.
##    Call `$Cli.help` for a plain string, or `Cli.help.display(<fd>)`
##    for styled output.
##
## The registration procs (`opt`_, `flag`_, `arg`_, `run`_, `cmd`_) also
## use a public module-level variable `bpCtx` to store their handlers there.
##
## Accessing help
## --------------
##
## Help is exposed through a simulated namespace backed by type-constrained
## templates. Each `.help` resolves to a `HelpText` object that facilitates
## styled output, built at compile time:
##
## .. code-block::
##   # with `buildParser`'s `helpName` argument set to "Cli":
##   Cli.help.display()          # root-level
##   Cli.foo.help.display()      # subcommand
##   Cli.help.display(stderr)
##   quit($Cli.foo.bar.help, 0)  # pass plain string if required
##
## .. note:: "bare" subcommands with only a `run` handler and no `arg`,
##    `opt`, or `flag` registrations do not receive a namespace entry. Accessing
##    `<helpName>.<subcmd>.help` for such a subcommand will not compile.
##    The default auto-generated help shows the help text of such command's
##    parent level.
##
## The namespace is available inside handler closures too, since it is
## injected before their declarations are emitted.
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
## directly inside the cmd's handler closure:
##
## .. code-block::
##   buildParser("git", "Cli", GnuMode):
##     cmd("add", "Add files to the index") do ():
##       arg("FILE", "File to add") do (val: string):
##         if val != "": options.addQueue.add(val)
##       flag('f', "force", "Add anything") do ():
##         options.add.force = true
##
## Nesting is supported.
##
## When a subcommand fires, there are two approaches to acting on it:
##
## **1. `run` handler**
##
## Register a command-handling hook for its level with `run`_. This handler
## is called once right after that subcommand's parser loop finishes, while
## still inside the generated subcommand's proc. This is often a simpler way
## to customize the control flow.
##
runnableExamples:
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
runnableExamples("-r:off"):
  type
    Cmd = enum cmdNone, cmdFilter
    Options = object
      cmd: Cmd
      filterCol, filterRe: string

  var options: Options
  buildParser("csvtool", "Cli", GnuMode):
    cmd("filter", "Filter rows by column value") do ():
      arg("COLUMN", "Column name") do (val: string):
        options.filterCol = val
        options.cmd = cmdFilter
      opt('r', "regex", "Match pattern", "RE") do (val: string):
        options.filterRe = val

  case options.cmd
    of cmdFilter:
      echo options # act on `options`
    of cmdNone:
      display(Cli.help); quit(1) # show help and signal error
##
## Error handling
## --------------
##
## Unknown options are routed to the installed error handler. The default
## handler is installed automatically. It writes the offending option and
## the relevant help text to `stderr`, then exits with code `1`. You can
## disable automatic error handling setting `helpAuto` in `ParserConfig`_.
##
## Override it with `onError`_ after the `buildParser` body:
##
## .. code-block::
##   buildParser("myapp", "Cli", GnuMode):
##     ...
##
##   onError do (e: ParseError):
##     stderr.writeLine "Unknown option: ", e.key
##     e.help.display(stderr) # styled help for the active subcommand level
##     quit(1)
##
## `ParseError` fields:
## - `key`: option/argument name as seen on the command line (no leading dashes).
## - `val`: associated value, or `""` for flags and bare unknowns.
## - `path`: active subcommand chain, e.g. `""` at root or `"remote add"`.
## - `help`: `HelpText` for the active parser level.
##
## There is one `onError` handler for all parser levels; `e.path` and `e.help`
## distinguish which level triggered the error.
##
## Principle of operation
## ----------------------
##
## The `macro buildParser`_:
##
## 1. Walks the `typed` body AST recursively, following the nesting
##    structure of command handling closures, and collects metadata.
## 2. Injects `const <helpName>`: a zero-cost typedesc namespace with
##    `help` templates for each level, each returning a `HelpText`.
## 3. Declares module-level `var bpCtx: BpContext` holding both the
##    handler seq and the error handler. The option registration procs
##    (`opt`, `flag`, `arg`, `run`, `onError`) store their handlers there.
## 4. Emits the passed body *verbatim*. `cmd` calls its closure immediately,
##    populating that subcommand's handlers before parsing begins.
## 5. Emits `<subcmd>Cmd` procs (innermost first), each with its own
##    `initOptParser` + `getopt` loop and a run handler, if registered.
## 6. Emits the root-level loop.

import std/[macros, parseopt, strutils, terminal]
from std/envvars import getEnv
export CliMode, ForegroundColor, Style

type
  HelpTag* = enum
    htPlain    ## whitespace, punctuation, "[options]" — never styled
    htProgName ## "csvtool", "csvtool filter" in the usage line
    htSection  ## "Usage:", "Arguments:", "Commands:", "Options:"
    htArg      ## positional name/metavar in listings and usage: "COLUMN"
    htMetavar  ## value placeholder after an opt key: "FILE", "CHAR"
    htShortKey ## short option form: "-v", "-s"
    htLongKey  ## long option form: "--verbose", "--output"
    htSubCmd   ## subcommand name in command listing: "filter", "version"

  HelpSpan = object
    text*: string
    tag*:  HelpTag

  HelpText* = seq[HelpSpan]

  ## Maps each semantic tag to a (foreground colour, style set) pair.
  ## `htPlain` entry is present for index completeness but is never applied.
  HelpPalette* = array[HelpTag, tuple[fg: ForegroundColor, style: set[Style]]]

const DefaultPalette*: HelpPalette = [
  htPlain:    (fgDefault, {}),
  htProgName: (fgDefault, {styleBright}),
  htSection:  (fgDefault, {styleDim}),
  htArg:      (fgCyan, {styleBright}),
  htMetavar:  (fgCyan, {}),
  htShortKey: (fgGreen, {styleBright}),
  htLongKey:  (fgBlue, {styleBright}),
  htSubCmd:   (fgMagenta, {styleBright})
]

proc write*(f: File; doc: HelpText) =
  ## Writes `doc` unstyled.
  for span in doc: f.write(span.text)
proc `$`*(doc: HelpText): string =
  for span in doc: result.add span.text

proc canStyle(f: File): bool =
  if getEnv("NO_COLOR").len > 0: return false
  let force = getEnv("CLICOLOR_FORCE")
  if force == "1" or force == "true": return true
  isatty(f)

proc display*(doc: HelpText; palette: HelpPalette; f: File = stdout) =
  ## Checks if `f` can and is allowed to emit colored output and,
  ## correspondingly, displays `doc` styled with `palette` or as a plain text.
  ##
  ## Respects the `NO_COLOR` and `CLICOLOR_FORCE` environmental variables.
  if not canStyle(f):
    f.write(doc)
  else:
    for span in doc:
      case span.tag
      of htPlain: f.write(span.text)
      else:
        let (fg, style) = palette[span.tag]
        f.styledWrite(style, fg, span.text)
  f.write('\n')
    
proc display*(doc: HelpText; f: File = stdout) =
  ## `display(HelpText,HelpPalette,File)`_ overload using `DefaultPalette`_.
  display(doc, DefaultPalette, f)

type
  OutStream* = enum
    ## Output stream selector for use in `ParserConfig` fields.
    osStdout = "stdout"
    osStderr = "stderr"

  ParserConfig* = object
    ## Compile-time configuration for `macro buildParser`_.
    ## Use `parseConfig`_ proc to selectively override the defaults.
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
  ## Reflects over `ParserConfig` field-by-field and emits:
  ## `proc parseConfig*(helpAuto = true, ...) : ParserConfig`
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

  let procName = ident("parseConfig")
  result = nnkProcDef.newTree(
     nnkPostfix.newTree(ident("*"), procName),
     newEmptyNode(), newEmptyNode(),
     formalParams,
     nnkPragma.newTree(ident("compiletime")),
     newEmptyNode(),
     nnkStmtList.newTree(objConstr))

emitParserConfigConstructor()

type
  OptKind = enum
    okOpt   ## --key=val / -k val
    okFlag  ## --flag / -f, no value
    okArg   ## positional argument
    okRun   ## post-loop hook

  OptSpec = object
    ## Compile-time metadata for one registration call.
    kind: OptKind
    short: char
    name: string
    help: string
    metavar: string
    absIdx: int ## absolute index into bpCtx.handlers; set during extractScope

  OptHandler* = proc (val: string) {.closure.}
  FlagHandler* = proc () {.closure.}
  ArgHandler* = proc (key: string) {.closure.}
  CmdRunHandler* = proc () {.closure.}

  Handler* = object
    ## Runtime storage for one registered handler closure.
    case kind: OptKind
    of okOpt: onOpt*: OptHandler
    of okFlag: onFlag*: FlagHandler
    of okArg: onArg*: ArgHandler
    of okRun: onRun*: CmdRunHandler

  ParseError* = object
    ## Describes an unknown option encountered during parsing.
    ##
    ## - `key`: option name as seen on the command line (no leading dashes).
    ## - `val`: associated value, or `""` for flags and bare unknowns.
    ## - `path`: active subcommand chain, e.g. `""` at root or `"remote add"`.
    ## - `help`: `HelpText` for the active parser level.
    ##   Call `$e.help` for a plain string or `e.help.display(stderr)` for
    ##   styled output.
    key*: string
    val*: string
    path*: string
    help*: HelpText

  ErrorHandler* = proc (e: ParseError) {.closure.}

  BpContext = object
    ## Keeps all the handlers.
    handlers: seq[Handler]
    onError: ErrorHandler

var bpCtx* {.global.}: BpContext ## A global storage for option and error handlers.

proc opt*(short: char; name, help, metavar: string; handler: OptHandler) =
  ## Registers a key-value option (`--name=val` / `-s val`).
  ##
  ## Pass `'\0'` for `short` to omit the short form; `""` for `name` to
  ## omit the long form.
  ##
  ## `metavar` is the value placeholder in usage lines.
  bpCtx.handlers.add Handler(kind: okOpt, onOpt: handler)

template optreg*(short: char; name, help, metavar: string; body: untyped) =
  ## Convenience wrapper for `opt`_. Injects `val` for the parsed value.
  opt(short, name, help, metavar, proc(val {.inject.}: string) = body)

proc flag*(short: char; name, help: string; handler: FlagHandler) =
  ## Registers a boolean flag (`--name` / `-s`), fired with no value.
  ##
  ## Pass `'\0'` for `short` to omit the short form; `""` for `name` to
  ## omit the long form.
  bpCtx.handlers.add Handler(kind: okFlag, onFlag: handler)

template flagreg*(short: char; name, help, metavar: string; body: untyped) =
  ## Convenience wrapper for `flag`_.
  flag(short, name, help, metavar, proc() = body)

proc arg*(name, help: string; handler: ArgHandler) =
  ## Registers a positional argument handler. Multiple `arg` calls
  ## are allowed per parser level.
  ##
  ## Parsed tokens are dispatched to handlers consecutively,
  ## in registration order, with the last handler receiving all
  ## overflow tokens.
  ##
  ## `name` is the placeholder shown in usage lines.
  bpCtx.handlers.add Handler(kind: okArg, onArg: handler)

template argreg*(name, help: string; body: untyped) =
  ## Convenience wrapper for `arg`_. Injects `key` for the parsed argument.
  arg(name, help, proc(key {.inject.}: string) = body)

proc run*(handler: CmdRunHandler) =
  ## Registers a closure called once after this parser level's loop finishes.
  ## Use it to perform actions in a command's own context immediately after
  ## its arguments have been parsed, without tracking state externally.
  ##
  ## Only one `run` handler is allowed per parser level.
  bpCtx.handlers.add Handler(kind: okRun, onRun: handler)

template runreg*(body: untyped) =
  ## Convenience wrapper for `run`_.
  run(proc () = body)

proc cmd*(name, help: string; cmdRegistrations: proc ()) =
  ## Declares a command and registers handlers for it and its options and
  ## arguments. This conceptually declares a parsing level, not a command
  ## handler. The `cmdRegistrations` closure is called **immediately**,
  ## not when the command is met during parsing.
  ##
  ## To act on a command during parsing, use `proc run`_.
  ## Use `arg`_, `flag`_, `opt`_, `run`_ or `cmd` itself inside
  ## `cmdRegistrations`, as you do at the root parser level.
  #
  # At runtime, when the token `name` is encountered, `cmd` delegates parsing
  # to the generated `<name>Cmd(remainingArgs)` proc with its own parser loop.
  cmdRegistrations()

template command(name, help: string, body: untyped) =
  cmd(name, help, proc() = body)

proc onError*(handler: ErrorHandler) =
  ## Installs a custom handler for unknown options across all parser levels.
  ## Call once after `macro buildParser`_. The same handler receives errors
  ## from any depth; inspect `e.path` and `e.help` to distinguish the level.
  ##
  ## The default handler writes the unknown option and the relevant help text
  ## to `stderr`, then exits with code 1.
  bpCtx.onError = handler

type
  ScopePath = seq[string]

  Scope = ref object
    ## Compile-time metadata for one parser level (root or subcommand).
    progName: string        ## top-level program name, unchanged at every level
    path: ScopePath     ## subcommand chain: @[] at root, @["a","b"] deeper
    specs: seq[OptSpec]  ## opt/flag/arg/run registrations at this level
    cmds: seq[CmdSpec]  ## subcommand registrations at this level
    autoHelp: OptSpec       ## injected help flag; kind == okFlag signals presence
    argIdxs: seq[int]      ## absolute bpCtx.handlers indexes of arg handlers, in order
    runIdx: int = -1      ## absolute bpCtx.handlers index of the run handler, or -1

  CmdSpec = object
    name: string ## token matched on the command line
    help: string
    procName: string ## generated proc name: name & "Cmd"
    scope: Scope

func hasShort(s: OptSpec): bool {.inline.} = s.short.ord >= 32
func hasLong(s: OptSpec): bool {.inline.} = s.name.len > 0
proc addStr(dest: var string; parts: varargs[string]) {.inline.}=
  for p in parts: dest.add p

proc addSpan(doc: var HelpText; tag: HelpTag; a: varargs[string]) =
  if a.len == 0: return
  if not (doc.len > 0 and doc[^1].tag == tag):
    doc.add HelpSpan(text: a[0], tag: tag)
    doc[^1].text.addStr a.toOpenArray(1, a.high)
  else:
    doc[^1].text.addStr a

template plain(doc: var HelpText; text: varargs[string]) = doc.addSpan(htPlain, text)

func specEntry(s: OptSpec): tuple[spans: HelpText, width: int] =
  ## Builds the left-column spans and computes their plain-text width in one pass.
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
    spans: HelpText  ## pre-built left-column spans (opts) or empty (arg/cmd)
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
      of htLongKey: d.add r.spans   ## opt/flag: spans already built by specEntry
      of htSubCmd:  d.addSpan(htSubCmd, r.name)
      else:         d.addSpan(htArg, r.name)
      d.plain(spaces(maxWidth - r.colWidth), sep)
      let lines = r.help.splitLines()
      d.plain(lines[0])
      for i in 1..high(lines): d.plain("\n", helpIndent, lines[i])

  result.section("Arguments", argRows, maxArg, htArg)
  result.section("Commands",  cmdRows, maxCmd, htSubCmd)
  result.section("Options",   optRows, maxOpt, htLongKey)

func isBareRunScope(scope: Scope): bool {.inline.} =
  scope.cmds.len == 0 and scope.argIdxs.len == 0 and
  scope.specs.len == (if scope.runIdx >= 0: 1 else: 0)

func toErrorPath(s: Scope): string = s.path.join(" ")

func generateHelp(s: Scope; cfg: ParserConfig): HelpText =
  var cmd = s.progName
  if s.path.len > 0: cmd.add " " & s.path.join(" ")
  generateHelp(cfg.helpPrefix, cmd, s.specs, s.cmds, s.autoHelp,
               cfg.fmtIndent, cfg.fmtColSep)

proc injectAutoHelp(scope: Scope; cfg: ParserConfig) =
  let (hShort, hLong) = cfg.helpFlag
  for s in scope.specs:
    if s.kind == okFlag and
       ((hShort.ord >= 32 and s.short == hShort) or
        (hLong.len > 0 and s.name == hLong)):
      return
  scope.autoHelp = OptSpec(kind: okFlag, short: hShort, name: hLong,
                           help: cfg.helpText)

proc extractScope(progName: string; body: NimNode; cfg: ParserConfig;
                  path: ScopePath; baseIdx: int): tuple[s: Scope, next: int] =
  ## Recursively walks `body` to build the Scope tree.
  ##
  ## `baseIdx` is this scope's first slot in `bpCtx.handlers`. Returns the
  ## scope and the total number of slots consumed by this scope and all its
  ## nested subcommands.
  var scope = Scope(progName: progName, path: path)
  var next = 0

  var stmts: seq[NimNode]
  for s in body:
    if s.kind == nnkStmtList:
      for inner in s: stmts.add inner
    else: stmts.add s

  for stmt in stmts:
    if stmt.kind in {nnkCommentStmt, nnkEmpty}: continue
    if stmt.kind notin {nnkCall, nnkCommand}:
      error("buildParser: only opt, flag, arg, run, cmd calls are allowed " &
            "in the parser body", stmt)
    let callee = $stmt[0]
    case callee
    of "opt", "flag":
      let isOpt = callee == "opt"
      let spec = OptSpec(kind: if isOpt: okOpt else: okFlag,
        short: chr(stmt[1].intVal.int),
        name: stmt[2].strVal,
        help: stmt[3].strVal,
        metavar: if isOpt: stmt[4].strVal else: "",
        absIdx: baseIdx + next)
      if not spec.hasShort and not spec.hasLong:
        error(callee & ": must have at least one of a short or long form", stmt)
      scope.specs.add spec
      inc next
    of "arg":
      let absIdx = baseIdx + next
      scope.argIdxs.add absIdx
      scope.specs.add OptSpec(kind: okArg,
                              name: stmt[1].strVal,
                              help: stmt[2].strVal,
                              absIdx: absIdx)
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
      let (childScope, childSize) = extractScope(progName, lambdaNode[^1],
                                                 cfg, path & name, baseIdx + next)
      next.inc(childSize)
      scope.cmds.add CmdSpec(name: name,
                             help: cmdHelp,
                             procName: name & "Cmd",
                             scope: childScope)
    else:
      error("buildParser: unexpected call '" & callee & "' — only opt, " &
            "flag, arg, run and cmd are allowed in the parser body", stmt)

  if cfg.helpAuto: scope.injectAutoHelp(cfg)
  (scope, next)

proc buildHelpNamespace(scope: Scope; typeName: NimNode; cfg: ParserConfig): NimNode =
  result = newStmtList()
  let docNode = newLit(generateHelp(scope, cfg))
  result.add quote do:
    type `typeName` = object
    template help(x: `typeName`): HelpText = @`docNode`
  for c in scope.cmds:
    if c.scope.isBareRunScope: continue
    let subTypeName = genSym(nskType, "SubCmdHelp")
    let cmdIdent = ident(c.name)
    result.add buildHelpNamespace(c.scope, subTypeName, cfg)
    result.add quote do:
      template `cmdIdent`(x: `typeName`): `subTypeName` = `subTypeName`()

proc helpDisplayCall(helpExpr, paletteSym, stream: NimNode;
                     useColors: bool): NimNode =
  if useColors: newCall(ident"display", helpExpr, paletteSym, stream)
  else: newCall(newDotExpr(stream, ident"write"), helpExpr)

proc buildParserLoop(scope: Scope;
                     mode: CliMode;
                     ctxNode, cmdlineNode, helpNode: NimNode;
                     cfg: ParserConfig;
                     paletteSym: NimNode): tuple[setup: NimNode, runCall: NimNode] =
  ## Emits the `initOptParser` + `getopt` loop for one parser level.
  let
    parser = ident("parser")
    key = ident("key")
    val = ident("val")
    kind = ident("kind")
    keyCase = nnkCaseStmt.newTree(key)
    pathLit = newLit(scope.toErrorPath())

  var shortNoVal: set[char]
  var longNoVal: seq[string]

  # Error call passes a HelpText, obtained from the help namespace template.
  let helpDocExpr = quote do: `helpNode`.help
  let onError = quote do:
    `ctxNode`.onError(ParseError(key: `key`, val: `val`,
                                 path: `pathLit`, help: `helpDocExpr`))

  for spec in scope.specs:
    if spec.kind notin {okOpt, okFlag}: continue
    let idx = newLit(spec.absIdx)
    let branch = nnkOfBranch.newTree()
    if spec.hasShort: branch.add newLit($spec.short)
    if spec.hasLong: branch.add newLit(spec.name)
    if spec.kind == okFlag:
      if spec.hasShort: shortNoVal.incl(spec.short)
      if spec.hasLong: longNoVal.add(spec.name)
      branch.add quote do: `ctxNode`.handlers[`idx`].onFlag()
    else:
      branch.add quote do: `ctxNode`.handlers[`idx`].onOpt(`val`)
    keyCase.add branch

  if scope.autoHelp.kind == okFlag:
    let
      ah = scope.autoHelp
      stream = ident($cfg.helpStream)
      exitCode = newLit(cfg.helpExitCode)
      branch = nnkOfBranch.newTree()
    if ah.hasShort:
      shortNoVal.incl(ah.short)
      branch.add newLit($ah.short)
    if ah.hasLong:
      longNoVal.add(ah.name)
      branch.add newLit(ah.name)
    let helpAction = helpDisplayCall(helpDocExpr, paletteSym, stream, cfg.useColors)
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
        `ctxNode`.handlers[`idxArr`[min(`argPos`, `high`)]].onArg(`key`)
        inc `argPos`
    else:
      onError

  let cmdArgBody =
    if scope.cmds.len > 0:
      let cmdCase = nnkCaseStmt.newTree(key)
      for c in scope.cmds:
        let procId = ident(c.procName)
        let cmdName = newLit(c.name)
        cmdCase.add nnkOfBranch.newTree(cmdName,
          quote do: `procId`(`parser`.remainingArgs()); break)
      cmdCase.add nnkElse.newTree(argBody)
      cmdCase
    else:
      argBody

  let shortNoValLit = newLit(shortNoVal)
  let longNoValLit = newLit(longNoVal)
  let initCall =
    if cmdlineNode.kind != nnkEmpty:
      quote do: initOptParser(`cmdlineNode`, shortNoVal = `shortNoValLit`,
                              longNoVal = `longNoValLit`, mode = `mode`)
    else:
      quote do: initOptParser(shortNoVal = `shortNoValLit`,
                              longNoVal = `longNoValLit`, mode = `mode`)

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

  if scope.runIdx >= 0:
    let ridx = newLit(scope.runIdx)
    result.runCall = quote do:
      if `ctxNode`.handlers[`ridx`].onRun != nil:
        `ctxNode`.handlers[`ridx`].onRun()
  else:
    result.runCall = newEmptyNode()

proc generateDispatchers(scope: Scope;
                         mode: CliMode;
                         ctxNode, helpNode: NimNode;
                         cfg: ParserConfig;
                         paletteSym: NimNode): NimNode =
  ## Emits `<subcmd>Cmd` procs for all subcommands, innermost first.
  result = newStmtList()
  for c in scope.cmds:
    let subHelp = newDotExpr(helpNode, ident(c.name))
    let displayHelp = if c.scope.isBareRunScope: helpNode else: subHelp
    result.add generateDispatchers(c.scope, mode, ctxNode, subHelp, cfg, paletteSym)
    let procId = ident(c.procName)
    let args = ident("args")
    let (loopSetup, loopRunCall) = buildParserLoop(c.scope, mode, ctxNode,
                                                   args, displayHelp, cfg, paletteSym)
    result.add quote do:
      proc `procId`(`args`: seq[string]) =
        if `args`.len > 0:
          `loopSetup`
        `loopRunCall`

macro buildParser*(cfg: static ParserConfig;
                   progName, helpName: static string;
                   mode: static CliMode;
                   body: typed): untyped =
  ## Generates a complete CLI parser from a declarative body.
  ## Only `arg`_, `cmd`_, `flag`_, `opt`_ and `run`_ calls are allowed inside.
  ##
  ## Injects one symbol into outer scope:
  ## - `const <helpName>`: a compile-time namespace where each `.help` property
  ##   returns a `HelpText`. Use `$` for a plain string or `display`_
  ##   for styled output.
  var colorPreamble = newStmtList()
  let paletteSym = genSym(nskConst, "bpPalette")
  if cfg.useColors:
    let palNode = newLit(cfg.palette)
    colorPreamble = quote do:
      const `paletteSym`: HelpPalette = `palNode`

  let
    (topScope, _) = extractScope(progName, body, cfg, @[], 0)
    helpId = ident(helpName)
    rootHelpType = genSym(nskType, "RootHelp")
    helpDefs = buildHelpNamespace(topScope, rootHelpType, cfg)

  let
    ctxId = bindSym("bpCtx")
    errStream = ident($cfg.errorStream)
    errExit = cfg.errorExitCode
    showHelp = cfg.errorShowHelp
    eIdent = ident("e")
    
  let helpPrintCall = helpDisplayCall(quote do: `eIdent`.help,
                        paletteSym, errStream, cfg.useColors)

  let defaultErrorHandler = quote do:
    `ctxId`.onError = proc (`eIdent`: ParseError) =
      let prefix = if `eIdent`.val.len > 0: `eIdent`.key & "=" & `eIdent`.val else: `eIdent`.key
      let context = if `eIdent`.path.len > 0: `eIdent`.path & ": " else: ""
      `errStream`.writeLine("Error: ", context, "unknown option '", prefix, "'")
      when `showHelp`:
        `errStream`.write("\n")
        `helpPrintCall`
      quit(`errExit`)

  let dispatchers = generateDispatchers(topScope, mode, ctxId, helpId, cfg, paletteSym)
  let (mainSetup, mainRunCall) = buildParserLoop(topScope, mode, ctxId,
                                                 newEmptyNode(), helpId, cfg, paletteSym)
  result = quote do:
    `colorPreamble`
    `helpDefs`
    const `helpId` = `rootHelpType`()
    `defaultErrorHandler`
    `body`
    `dispatchers`
    `mainSetup`
    `mainRunCall`

  if cfg.debug: hint("buildParser expansion:\n" & result.repr)

template buildParser*(progName, helpName: static string;
                      mode: static CliMode;
                      body: typed): untyped =
  ## Convenience overload using the default `ParserConfig`.
  buildParser(ParserConfig(), progName, helpName, mode, body)

when isMainModule:
  type Options = object
    separator: string = ","
    output: string
    count: int
    filterCol: string
    filterRe: string

  var options = Options()

  buildParser(parseConfig(debug = true), "csvtool", "Cli", NimMode):
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

  doAssert $Cli.help == """Usage: csvtool [options] <filter> <version>

Commands:
  filter   Filter rows by column value
  version  Displays version and exits

Options:
  -s, --separator=CHAR  Field separator
  -c, --count=NUM       Number of rows to process
  --output=FILE         Output file
  -h, --help            Show this help and exit"""

  doAssert $Cli.filter.help == """Usage: csvtool filter [options] COLUMN PATTERN

Arguments:
  COLUMN   Column name to match on
           Uses the provided pattern
  PATTERN  Value to match

Options:
  -h, --help  Show this help and exit"""
