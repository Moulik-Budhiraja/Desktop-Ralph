import Foundation

struct OXAParser {
    static func parse(_ source: String) throws -> OXAProgram {
        var parser = Implementation(source: source)
        return try parser.parseProgram()
    }

    private struct Token {
        enum Kind: Equatable {
            case word(String)
            case string(String)
            case semicolon
            case plus
            case eof
        }

        let kind: Kind
    }

    private struct Lexer {
        private let scalars: [Character]
        private var index = 0

        init(source: String) {
            self.scalars = Array(source)
        }

        mutating func nextToken() throws -> Token {
            self.consumeWhitespace()
            guard self.index < self.scalars.count else { return Token(kind: .eof) }

            let character = self.scalars[self.index]
            switch character {
            case ";":
                self.index += 1
                return Token(kind: .semicolon)
            case "+":
                self.index += 1
                return Token(kind: .plus)
            case "\"":
                return try self.readString()
            default:
                return self.readWord()
            }
        }

        private mutating func readString() throws -> Token {
            self.index += 1
            var value = ""
            while self.index < self.scalars.count {
                let character = self.scalars[self.index]
                self.index += 1
                if character == "\"" {
                    return Token(kind: .string(value))
                }
                value.append(character)
            }
            throw OXAActionError.parse("Unterminated string literal.")
        }

        private mutating func readWord() -> Token {
            var value = ""
            while self.index < self.scalars.count {
                let character = self.scalars[self.index]
                if character.isWhitespace || character == ";" || character == "+" {
                    break
                }
                value.append(character)
                self.index += 1
            }
            return Token(kind: .word(value))
        }

        private mutating func consumeWhitespace() {
            while self.index < self.scalars.count, self.scalars[self.index].isWhitespace {
                self.index += 1
            }
        }
    }

    private struct Implementation {
        private static let modifierSet: Set<String> = ["cmd", "ctrl", "alt", "shift", "fn"]
        private static let namedBaseKeys: Set<String> = [
            "enter", "tab", "space", "escape", "backspace", "delete",
            "home", "end", "page_up", "page_down",
            "up", "down", "left", "right",
        ]

        private var lexer: Lexer
        private var lookahead: Token

        init(source: String) {
            var lexer = Lexer(source: source)
            self.lookahead = (try? lexer.nextToken()) ?? Token(kind: .eof)
            self.lexer = lexer
        }

        mutating func parseProgram() throws -> OXAProgram {
            var statements: [OXAStatement] = []

            while !self.isEOF {
                statements.append(try self.parseStatement())
                try self.expectSemicolon()
            }

            return OXAProgram(statements: statements)
        }

        private var isEOF: Bool {
            if case .eof = self.lookahead.kind { return true }
            return false
        }

        private mutating func parseStatement() throws -> OXAStatement {
            let keyword = try self.expectWord().lowercased()
            switch keyword {
            case "send":
                return try self.parseSendStatement()
            case "read":
                let attributeName = try self.expectWord()
                _ = try self.expectWord("from")
                return .readAttribute(attributeName: attributeName, targetRef: try self.expectElementReference())
            case "sleep":
                return .sleep(milliseconds: try self.expectInteger())
            case "open":
                return .open(app: try self.expectString())
            case "close":
                return .close(app: try self.expectString())
            default:
                throw OXAActionError.parse("Unexpected statement keyword '\(keyword)'.")
            }
        }

        private mutating func parseSendStatement() throws -> OXAStatement {
            let action = try self.expectWord().lowercased()
            switch action {
            case "text":
                let text = try self.expectString()
                if self.consumeWordIfPresent("as") {
                    _ = try self.expectWord("keys")
                    _ = try self.expectWord("to")
                    return .sendTextAsKeys(text: text, targetRef: try self.expectElementReference())
                }
                _ = try self.expectWord("to")
                return .sendText(text: text, targetRef: try self.expectElementReference())
            case "click":
                _ = try self.expectWord("to")
                return .sendClick(targetRef: try self.expectElementReference())
            case "right":
                _ = try self.expectWord("click")
                _ = try self.expectWord("to")
                return .sendRightClick(targetRef: try self.expectElementReference())
            case "drag":
                let sourceRef = try self.expectElementReference()
                _ = try self.expectWord("to")
                return .sendDrag(sourceRef: sourceRef, targetRef: try self.expectElementReference())
            case "hotkey":
                let chord = try self.parseHotkeyChord()
                _ = try self.expectWord("to")
                return .sendHotkey(chord: chord, targetRef: try self.expectElementReference())
            case "scroll":
                if self.consumeWordIfPresent("to") {
                    return .sendScrollIntoView(targetRef: try self.expectElementReference())
                }

                let directionValue = try self.expectWord().lowercased()
                guard let direction = OXAScrollDirection(rawValue: directionValue) else {
                    throw OXAActionError.parse("Unsupported scroll direction '\(directionValue)'.")
                }
                _ = try self.expectWord("to")
                return .sendScroll(direction: direction, targetRef: try self.expectElementReference())
            default:
                throw OXAActionError.parse("Unsupported send action '\(action)'.")
            }
        }

        private mutating func parseHotkeyChord() throws -> OXAHotkeyChord {
            var parts = [self.normalizeHotkeyToken(try self.expectWord())]
            while self.consumePlusIfPresent() {
                parts.append(self.normalizeHotkeyToken(try self.expectWord()))
            }

            guard let baseKey = parts.last else {
                throw OXAActionError.parse("Hotkey is empty.")
            }

            let modifiers = Array(parts.dropLast())
            for modifier in modifiers where !Self.modifierSet.contains(modifier) {
                throw OXAActionError.parse("Invalid hotkey modifier '\(modifier)'.")
            }
            guard Set(modifiers).count == modifiers.count else {
                throw OXAActionError.parse("Hotkey modifiers must be unique.")
            }
            guard !Self.modifierSet.contains(baseKey), self.isSupportedBaseKey(baseKey) else {
                throw OXAActionError.parse("Unsupported hotkey base key '\(baseKey)'.")
            }

            return OXAHotkeyChord(modifiers: modifiers, baseKey: baseKey)
        }

        private func isSupportedBaseKey(_ value: String) -> Bool {
            if value.count == 1, let scalar = value.unicodeScalars.first {
                return CharacterSet.alphanumerics.contains(scalar)
            }
            if value.first == "f", let number = Int(value.dropFirst()), (1...24).contains(number) {
                return true
            }
            return Self.namedBaseKeys.contains(value)
        }

        private func normalizeHotkeyToken(_ token: String) -> String {
            let lowered = token.lowercased().replacingOccurrences(of: "-", with: "_")
            let aliases = [
                "command": "cmd",
                "control": "ctrl",
                "option": "alt",
                "opt": "alt",
                "return": "enter",
                "esc": "escape",
                "pageup": "page_up",
                "pagedown": "page_down",
                "arrowup": "up",
                "arrowdown": "down",
                "arrowleft": "left",
                "arrowright": "right",
            ]
            return aliases[lowered] ?? lowered
        }

        private mutating func expectSemicolon() throws {
            guard case .semicolon = self.lookahead.kind else {
                throw OXAActionError.parse("Expected ';' after statement.")
            }
            try self.advance()
        }

        private mutating func expectWord(_ expected: String? = nil) throws -> String {
            guard case let .word(value) = self.lookahead.kind else {
                throw OXAActionError.parse("Expected identifier.")
            }
            if let expected, value.lowercased() != expected.lowercased() {
                throw OXAActionError.parse("Expected '\(expected)'.")
            }
            try self.advance()
            return value
        }

        private mutating func expectString() throws -> String {
            guard case let .string(value) = self.lookahead.kind else {
                throw OXAActionError.parse("Expected string literal.")
            }
            try self.advance()
            return value
        }

        private mutating func expectInteger() throws -> Int {
            let text = try self.expectWord()
            guard let value = Int(text) else {
                throw OXAActionError.parse("Expected integer value.")
            }
            return value
        }

        private mutating func expectElementReference() throws -> String {
            let value = try self.expectWord().lowercased()
            guard value.count == 9, value.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "0123456789abcdef").contains($0)
            }) else {
                throw OXAActionError.parse("Element references must be exactly 9 hex characters.")
            }
            return value
        }

        private mutating func consumePlusIfPresent() -> Bool {
            guard case .plus = self.lookahead.kind else { return false }
            try? self.advance()
            return true
        }

        private mutating func consumeWordIfPresent(_ expected: String) -> Bool {
            guard case let .word(value) = self.lookahead.kind, value.lowercased() == expected.lowercased() else {
                return false
            }
            try? self.advance()
            return true
        }

        private mutating func advance() throws {
            self.lookahead = try self.lexer.nextToken()
        }
    }
}
