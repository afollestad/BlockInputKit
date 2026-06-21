import Foundation

/// Parsed representation of a normalized GFM-style pipe table.
///
/// The model keeps cell source ranges relative to the normalized Markdown stored
/// in a table block so editor cells can safely map local edits, formatting, and
/// links back to block text. Cells are single-line inline Markdown fragments;
/// embedded newlines are collapsed before export.
struct BlockInputTable: Equatable {
    enum Alignment: Equatable {
        case left
        case center
        case right
    }

    struct Cell: Equatable {
        var text: String
        var sourceRange: NSRange
    }

    var header: [Cell]
    var bodyRows: [[Cell]]
    var alignments: [Alignment]
    var markdown: String

    var columnCount: Int {
        header.count
    }

    var firstBodyCellRange: NSRange? {
        bodyRows.first?.first?.sourceRange
    }

    var firstHeaderCellRange: NSRange? {
        header.first?.sourceRange
    }

    private init(
        header: [Cell],
        bodyRows: [[Cell]],
        alignments: [Alignment],
        markdown: String
    ) {
        self.header = header
        self.bodyRows = bodyRows
        self.alignments = alignments
        self.markdown = markdown
    }

    init?(markdown: String) {
        let lines = blockInputOuterBlankTrimmedTableLines(in: markdown)
        guard let parsed = Self.parse(lines: lines, startIndex: 0),
              parsed.nextIndex == lines.count else {
            return nil
        }
        self = parsed.table
    }

    static func parse(lines: [String], startIndex: Int) -> (table: BlockInputTable, nextIndex: Int)? {
        guard lines.indices.contains(startIndex + 1),
              lines[startIndex].contains("|"),
              lines[startIndex + 1].contains("|"),
              let headerCells = parseContentCells(lines[startIndex]),
              let alignments = parseDelimiterCells(lines[startIndex + 1]),
              !headerCells.isEmpty,
              headerCells.count == alignments.count else {
            return nil
        }

        var bodyRows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count,
              isContentLine(lines[index]),
              let bodyCells = parseContentCells(lines[index]) {
            bodyRows.append(padded(Array(bodyCells.prefix(headerCells.count)), to: headerCells.count))
            index += 1
        }

        let table = normalized(
            header: padded(headerCells, to: headerCells.count),
            bodyRows: bodyRows,
            alignments: alignments
        )
        return (table, index)
    }

    func replacingCellText(row: Row, column: Int, text: String) -> BlockInputTable? {
        guard (0..<columnCount).contains(column) else {
            return nil
        }
        var headerText = header.map(\.text)
        var bodyText = bodyRows.map { $0.map(\.text) }
        switch row {
        case .header:
            headerText[column] = Self.normalizedCellText(text)
        case .body(let rowIndex):
            guard bodyText.indices.contains(rowIndex) else {
                return nil
            }
            bodyText[rowIndex][column] = Self.normalizedCellText(text)
        }
        return Self.normalized(header: headerText, bodyRows: bodyText, alignments: alignments)
    }

    func appendingBodyRow() -> BlockInputTable {
        let emptyRow = Array(repeating: "", count: columnCount)
        return Self.normalized(
            header: header.map(\.text),
            bodyRows: bodyRows.map { $0.map(\.text) } + [emptyRow],
            alignments: alignments
        )
    }

    func appendingColumn() -> BlockInputTable {
        let headerText = header.map(\.text) + [""]
        let bodyText = bodyRows.map { $0.map(\.text) + [""] }
        return Self.normalized(header: headerText, bodyRows: bodyText, alignments: alignments + [.left])
    }

    func deletingBodyRow(_ rowIndex: Int, keepsLastBodyRow: Bool) -> BlockInputTable? {
        guard bodyRows.indices.contains(rowIndex) else {
            return nil
        }
        var bodyText = bodyRows.map { $0.map(\.text) }
        bodyText.remove(at: rowIndex)
        if keepsLastBodyRow, bodyText.isEmpty {
            bodyText = [Array(repeating: "", count: columnCount)]
        }
        return Self.normalized(header: header.map(\.text), bodyRows: bodyText, alignments: alignments)
    }

    func deletingColumn(_ column: Int) -> BlockInputTable? {
        guard columnCount > 1, (0..<columnCount).contains(column) else {
            return nil
        }
        var headerText = header.map(\.text)
        var bodyText = bodyRows.map { $0.map(\.text) }
        var updatedAlignments = alignments
        headerText.remove(at: column)
        updatedAlignments.remove(at: column)
        for rowIndex in bodyText.indices {
            bodyText[rowIndex].remove(at: column)
        }
        return Self.normalized(header: headerText, bodyRows: bodyText, alignments: updatedAlignments)
    }

    static func normalized(
        header: [String],
        bodyRows: [[String]],
        alignments: [Alignment]
    ) -> BlockInputTable {
        let columnCount = max(header.count, alignments.count, bodyRows.map(\.count).max() ?? 0)
        let normalizedHeader = padded(header.map(normalizedCellText), to: columnCount)
        let normalizedRows = bodyRows.map { padded($0.map(normalizedCellText), to: columnCount) }
        let normalizedAlignments = padded(alignments, to: columnCount)
        let escapedHeader = normalizedHeader.map(escapeCellText)
        let escapedRows = normalizedRows.map { $0.map(escapeCellText) }
        let delimiters = normalizedAlignments.map(delimiterMarkdown)
        let widths: [Int] = (0..<columnCount).map { column in
            var columnTexts: [String] = [escapedHeader[column], delimiters[column]]
            columnTexts.append(contentsOf: escapedRows.map { $0[column] })
            let lengths = columnTexts.map(\.utf16Length)
            return lengths.max() ?? 3
        }

        var markdownLines: [String] = []
        let headerLine = markdownLine(cells: escapedHeader, widths: widths, lineStart: 0)
        markdownLines.append(headerLine.line)
        let delimiterLineStart = markdownLines[0].utf16Length + 1
        markdownLines.append(markdownLine(cells: delimiters, widths: widths, lineStart: delimiterLineStart).line)

        var bodyCells: [[Cell]] = []
        var currentLineStart = delimiterLineStart + markdownLines[1].utf16Length + 1
        for row in escapedRows {
            let bodyLine = markdownLine(cells: row, widths: widths, lineStart: currentLineStart)
            markdownLines.append(bodyLine.line)
            bodyCells.append(bodyLine.cells)
            currentLineStart += bodyLine.line.utf16Length + 1
        }

        return BlockInputTable(
            header: zip(headerLine.cells, normalizedHeader).map { cell, text in
                Cell(text: text, sourceRange: cell.sourceRange)
            },
            bodyRows: zip(bodyCells, normalizedRows).map { rowCells, rowTexts in
                zip(rowCells, rowTexts).map { cell, text in
                    Cell(text: text, sourceRange: cell.sourceRange)
                }
            },
            alignments: normalizedAlignments,
            markdown: markdownLines.joined(separator: "\n")
        )
    }

    enum Row: Equatable {
        case header
        case body(Int)
    }

    private static func parseContentCells(_ line: String) -> [String]? {
        let cells = splitCells(in: line)
        guard !cells.isEmpty else {
            return nil
        }
        return cells.map { unescapeCellText(String(line[$0.trimmingWhitespace(in: line)])) }
    }

    private static func parseDelimiterCells(_ line: String) -> [Alignment]? {
        let delimiterCells = splitCells(in: line)
        guard !delimiterCells.isEmpty else {
            return nil
        }
        let alignments = delimiterCells.compactMap { alignment(for: String(line[$0.trimmingWhitespace(in: line)])) }
        return alignments.count == delimiterCells.count ? alignments : nil
    }

    private static func alignment(for delimiter: String) -> Alignment? {
        guard delimiter.contains("-"),
              delimiter.allSatisfy({ $0 == ":" || $0 == "-" }),
              delimiter.filter({ $0 == "-" }).count >= 3 else {
            return nil
        }
        let startsWithColon = delimiter.first == ":"
        let endsWithColon = delimiter.last == ":"
        if startsWithColon, endsWithColon {
            return .center
        }
        if endsWithColon {
            return .right
        }
        return .left
    }

    private static func splitCells(in line: String) -> [Range<String.Index>] {
        let bounds = contentBounds(in: line)
        var ranges: [Range<String.Index>] = []
        var cellStart = bounds.lowerBound
        var index = bounds.lowerBound
        var codeDelimiterLength = 0

        while index < bounds.upperBound {
            let character = line[index]
            if character == "`" {
                let runLength = backtickRunLength(in: line, from: index)
                if codeDelimiterLength == 0 {
                    if hasClosingBacktickRun(in: line, from: line.index(index, offsetBy: runLength), length: runLength) {
                        codeDelimiterLength = runLength
                    }
                } else if runLength == codeDelimiterLength {
                    codeDelimiterLength = 0
                }
                index = line.index(index, offsetBy: runLength)
                continue
            }
            if character == "|", codeDelimiterLength == 0, !isEscapedPipe(in: line, at: index) {
                ranges.append(cellStart..<index)
                cellStart = line.index(after: index)
            }
            index = line.index(after: index)
        }
        ranges.append(cellStart..<bounds.upperBound)
        return ranges
    }

    private static func contentBounds(in line: String) -> Range<String.Index> {
        var lowerBound = line.startIndex
        var upperBound = line.endIndex
        if lowerBound < upperBound, line[lowerBound] == "|" {
            lowerBound = line.index(after: lowerBound)
        }
        if lowerBound < upperBound {
            let lastIndex = line.index(before: upperBound)
            if line[lastIndex] == "|", !isEscapedPipe(in: line, at: lastIndex) {
                upperBound = lastIndex
            }
        }
        return lowerBound..<upperBound
    }

    private static func backtickRunLength(in line: String, from index: String.Index) -> Int {
        var length = 0
        var cursor = index
        while cursor < line.endIndex, line[cursor] == "`" {
            length += 1
            cursor = line.index(after: cursor)
        }
        return length
    }

    private static func hasClosingBacktickRun(in line: String, from index: String.Index, length: Int) -> Bool {
        var cursor = index
        while cursor < line.endIndex {
            guard line[cursor] == "`" else {
                cursor = line.index(after: cursor)
                continue
            }
            let runLength = backtickRunLength(in: line, from: cursor)
            if runLength == length {
                return true
            }
            cursor = line.index(cursor, offsetBy: runLength)
        }
        return false
    }

    private static func isEscapedPipe(in line: String, at index: String.Index) -> Bool {
        guard index > line.startIndex else {
            return false
        }
        var slashCount = 0
        var cursor = line.index(before: index)
        while true {
            guard line[cursor] == "\\" else {
                break
            }
            slashCount += 1
            guard cursor > line.startIndex else {
                break
            }
            cursor = line.index(before: cursor)
        }
        return slashCount % 2 == 1
    }

    private static func markdownLine(
        cells: [String],
        widths: [Int],
        lineStart: Int
    ) -> (line: String, cells: [Cell]) {
        var line = "|"
        var outputCells: [Cell] = []
        var cursor = lineStart + 1
        for (index, cell) in cells.enumerated() {
            line += " "
            cursor += 1
            outputCells.append(Cell(text: "", sourceRange: NSRange(location: cursor, length: cell.utf16Length)))
            line += cell
            cursor += cell.utf16Length
            let padding = max(0, widths[index] - cell.utf16Length)
            if padding > 0 {
                line += String(repeating: " ", count: padding)
                cursor += padding
            }
            line += " |"
            cursor += 2
        }
        return (line, outputCells)
    }

    private static func delimiterMarkdown(for alignment: Alignment) -> String {
        switch alignment {
        case .left:
            return "---"
        case .center:
            return ":---:"
        case .right:
            return "---:"
        }
    }

    private static func normalizedCellText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func escapeCellText(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var codeDelimiterLength = 0
        while index < text.endIndex {
            let character = text[index]
            if character == "`" {
                let runLength = backtickRunLength(in: text, from: index)
                output += String(text[index..<text.index(index, offsetBy: runLength)])
                if codeDelimiterLength == 0 {
                    if hasClosingBacktickRun(in: text, from: text.index(index, offsetBy: runLength), length: runLength) {
                        codeDelimiterLength = runLength
                    }
                } else if runLength == codeDelimiterLength {
                    codeDelimiterLength = 0
                }
                index = text.index(index, offsetBy: runLength)
                continue
            }
            if codeDelimiterLength == 0 {
                if character == "\\" {
                    output += "\\\\"
                } else if character == "|" {
                    output += "\\|"
                } else {
                    output.append(character)
                }
            } else {
                output.append(character)
            }
            index = text.index(after: index)
        }
        return output
    }

    private static func unescapeCellText(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var codeDelimiterLength = 0
        while index < text.endIndex {
            let character = text[index]
            if character == "`" {
                let runLength = backtickRunLength(in: text, from: index)
                let runEnd = text.index(index, offsetBy: runLength)
                output += String(text[index..<runEnd])
                if codeDelimiterLength == 0 {
                    if hasClosingBacktickRun(in: text, from: runEnd, length: runLength) {
                        codeDelimiterLength = runLength
                    }
                } else if runLength == codeDelimiterLength {
                    codeDelimiterLength = 0
                }
                index = runEnd
                continue
            }
            if codeDelimiterLength == 0, character == "\\" {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex, isEscapedCellCharacter(text[nextIndex]) {
                    output.append(text[nextIndex])
                    index = text.index(after: nextIndex)
                    continue
                }
            }
            output.append(character)
            index = text.index(after: index)
        }
        return output
    }

    private static func isEscapedCellCharacter(_ character: Character) -> Bool {
        character == "\\" || character == "|"
    }

}

private func blockInputOuterBlankTrimmedTableLines(in markdown: String) -> [String] {
    let lines = BlockInputLineBreaks.lines(in: markdown)
    guard let firstContentIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
          let lastContentIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        return lines
    }
    return Array(lines[firstContentIndex...lastContentIndex])
}

extension BlockInputTable {
    static func isContentLine(_ line: String) -> Bool {
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line.contains("|")
    }
}

private extension BlockInputTable {
    static func padded<T>(_ values: [T], to count: Int) -> [T] where T: ExpressibleByStringLiteral {
        values + Array(repeating: "", count: max(0, count - values.count))
    }

    static func padded(_ values: [Alignment], to count: Int) -> [Alignment] {
        values + Array(repeating: .left, count: max(0, count - values.count))
    }
}

private extension String {
    var utf16Length: Int {
        (self as NSString).length
    }
}

private extension Range where Bound == String.Index {
    func trimmingWhitespace(in string: String) -> Range<String.Index> {
        var lower = lowerBound
        var upper = upperBound
        while lower < upper, string[lower].isWhitespace {
            lower = string.index(after: lower)
        }
        while lower < upper {
            let previous = string.index(before: upper)
            guard string[previous].isWhitespace else {
                break
            }
            upper = previous
        }
        return lower..<upper
    }
}
