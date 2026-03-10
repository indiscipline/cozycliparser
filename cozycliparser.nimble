# Package
version       = "0.1.0"
author        = "Kirill I."
description   = "CLI parser builder, a convenience wrapper over `std/parseopt`"
license       = "GPL-2.0-or-later"
srcDir        = "."

# Dependencies

requires "nim >= 2.3.1"

import std/[pegs, os, strutils]

const
  SRC = "cozycliparser.nim"
  exampleFile = "readmeexample.nim"
  readmeFile = "README.md"
  injectFrom = "<!-- EXAMPLE_START -->"
  injectTo = "<!-- EXAMPLE_END -->"

task updatereadme, "Runs the example file and injects its source into README.md":
  echo "Executing: nim r ", exampleFile
  let (output, exitCode) = gorgeEx("nim r " & exampleFile)
  if exitCode != 0:
    echo "Execution failed! Output:"
    quit(output, 1)
  let sourceCode = readFile(exampleFile).strip()
  # `@` is non-greedy, matches anything including newlines.
  let pattern = peg("'" & injectFrom & "' @ '" & injectTo & "'")
  let replacement = injectFrom & "\n```nim\n" & sourceCode & "\n```\n" & injectTo

  if not fileExists(readmeFile):
    echo "Error: ", readmeFile, " not found!"
    quit(1)

  let oldContent = readFile(readmeFile)
  let newContent = oldContent.replace(pattern, replacement)

  if oldContent != newContent:
    writeFile(readmeFile, newContent)
    echo "Success! Injected ", exampleFile, " into ", readmeFile
  else:
    echo "Nothing to update. (Check injection markers!)"

task updatedocs, "Regenerated `docs/index.html`":
  exec("nim doc -o:docs/index.html " & SRC)
