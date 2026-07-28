import Foundation

enum BlockInputCompletionTokenParsing {
    static func tokenStart(before utf16Offset: Int, in text: NSString) -> Int {
        var location = min(max(utf16Offset, 0), text.length)
        while location > 0 {
            let previousLocation = location - 1
            let character = text.character(at: previousLocation)
            if isTokenBoundary(character) {
                return location
            }
            location = previousLocation
        }
        return 0
    }

    static func rawSlashCommandTokenRange(
        startingAt tokenStart: Int,
        in text: NSString,
        availability: BlockInputSlashCommandAvailability,
        isDocumentStartBlock: Bool
    ) -> NSRange? {
        guard tokenStart >= 0,
              tokenStart < text.length,
              text.character(at: tokenStart) == slash,
              isTokenStartBoundary(tokenStart, in: text),
              allowsSlashCommandToken(
                  startingAt: tokenStart,
                  availability: availability,
                  isDocumentStartBlock: isDocumentStartBlock
              ) else {
            return nil
        }
        var tokenEnd = tokenStart + 1
        while tokenEnd < text.length,
              !isTokenBoundary(text.character(at: tokenEnd)) {
            tokenEnd += 1
        }
        guard tokenEnd > tokenStart + 1 else {
            return nil
        }
        return NSRange(location: tokenStart, length: tokenEnd - tokenStart)
    }

    /// Range of a literal `@`-prefixed file path token such as `@/usr/bin/env`
    /// or `@~/notes.md`. The `@` must sit at a token boundary and be followed
    /// by an absolute (`/`) or home-relative (`~/`) path with at least one
    /// character after the path prefix, which keeps mentions like `@channel`
    /// and mid-word `user@host` from matching.
    static func rawFileMentionTokenRange(startingAt tokenStart: Int, in text: NSString) -> NSRange? {
        guard tokenStart >= 0,
              tokenStart < text.length,
              text.character(at: tokenStart) == atSign,
              isTokenStartBoundary(tokenStart, in: text) else {
            return nil
        }
        var tokenEnd = tokenStart + 1
        while tokenEnd < text.length,
              !isTokenBoundary(text.character(at: tokenEnd)) {
            tokenEnd += 1
        }
        let pathStart = tokenStart + 1
        let pathLength = tokenEnd - pathStart
        guard pathLength >= 2 else {
            return nil
        }
        switch text.character(at: pathStart) {
        case slash:
            break
        case tilde where text.character(at: pathStart + 1) == slash && pathLength >= 3:
            break
        default:
            return nil
        }
        return NSRange(location: tokenStart, length: tokenEnd - tokenStart)
    }

    /// Whether `path` can serialize back into a valid `@path` mention token:
    /// an absolute or home-relative prefix with at least one character after
    /// it and no token-boundary characters that would truncate the token.
    static func isValidRawFileMentionPath(_ path: String) -> Bool {
        let nsPath = path as NSString
        guard nsPath.length >= 2 else {
            return false
        }
        switch nsPath.character(at: 0) {
        case slash:
            break
        case tilde where nsPath.length >= 3 && nsPath.character(at: 1) == slash:
            break
        default:
            return false
        }
        for index in 0..<nsPath.length where isTokenBoundary(nsPath.character(at: index)) {
            return false
        }
        return true
    }

    static func allowsSlashCommandToken(
        startingAt tokenStart: Int,
        availability: BlockInputSlashCommandAvailability,
        isDocumentStartBlock: Bool
    ) -> Bool {
        switch availability {
        case .anywhere:
            return true
        case .documentStart:
            return tokenStart == 0 && isDocumentStartBlock
        }
    }

    static func isTokenBoundary(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(Int(character)) else {
            return false
        }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return true
        }
        return ["(", "[", "{", "<", "\"", "'"].contains(Character(scalar))
    }

    private static func isTokenStartBoundary(_ location: Int, in text: NSString) -> Bool {
        location == 0 || isTokenBoundary(text.character(at: location - 1))
    }
}

private let slash: unichar = 0x2F
private let atSign: unichar = 0x40
private let tilde: unichar = 0x7E
