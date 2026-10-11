import Foundation

let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
FileHandle.standardError.write(Data("vrai-askpass: no Vrai window is answering prompts, so \"\(prompt)\" was declined.\n".utf8))
exit(1)
