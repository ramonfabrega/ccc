import Foundation

// ccc — one binary, two faces. No arguments: the app. A subcommand: the CLI,
// which runs headless over the same CCCKit. Parity is the point (CLAUDE.md
// "the human and the agent are first-class"): every click has a twin here.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty {
    App.main()
} else {
    exit(await CLI.run(arguments))
}
