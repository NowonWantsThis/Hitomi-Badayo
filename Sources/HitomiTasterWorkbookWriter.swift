import Foundation

enum HitomiTasterWorkbookWriter {
    static func write(
        results: [HitomiTasterResult],
        model: HitomiTasterModel,
        referenceCount: Int,
        accuracy: Double,
        to destination: URL
    ) throws {
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiTaster-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: package)
        }

        try createPackage(results: results, model: model, referenceCount: referenceCount, accuracy: accuracy, at: package)
        try? FileManager.default.removeItem(at: destination)
        try ZipArchiveWriter.archiveDirectory(package, to: destination)
    }

    private static func createPackage(
        results: [HitomiTasterResult],
        model: HitomiTasterModel,
        referenceCount: Int,
        accuracy: Double,
        at package: URL
    ) throws {
        let relationships = package.appendingPathComponent("_rels", isDirectory: true)
        let workbookRelationships = package.appendingPathComponent("xl/_rels", isDirectory: true)
        let worksheets = package.appendingPathComponent("xl/worksheets", isDirectory: true)

        try FileManager.default.createDirectory(at: relationships, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workbookRelationships, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worksheets, withIntermediateDirectories: true)

        try contentTypes.write(to: package.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelationships.write(to: relationships.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try workbookXML.write(to: package.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
        try workbookRels.write(to: workbookRelationships.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)
        try stylesXML.write(to: package.appendingPathComponent("xl/styles.xml"), atomically: true, encoding: .utf8)
        try worksheetXML(results: results, model: model, referenceCount: referenceCount, accuracy: accuracy)
            .write(to: worksheets.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)
    }

    private static func worksheetXML(
        results: [HitomiTasterResult],
        model: HitomiTasterModel,
        referenceCount: Int,
        accuracy: Double
    ) -> String {
        var rows: [String] = []
        rows.append(row(1, [text("Hitomi Taster"), blank, blank, blank, blank, blank, blank, blank, blank, blank], style: 1))
        rows.append(row(2, [text("Reference Works"), number(referenceCount), text("Model"), text(model.originalLabel), text("Accuracy"), number(accuracy)]))
        rows.append(row(3, [text("Rank"), text("Artist"), text("Score"), text("Confidence"), text("Query"), text("Jobs"), text("History"), text("Bookmarks"), text("Related Terms"), text("Example")], style: 1))

        for (offset, result) in results.enumerated() {
            rows.append(row(offset + 4, [
                number(result.rank),
                text(result.name),
                number(result.adjustedScore),
                number(result.confidence),
                text(result.queryToken),
                number(result.jobCount),
                number(result.historyCount),
                number(result.bookmarkCount),
                text(result.relatedTerms.joined(separator: ", ")),
                text(result.exampleTitle)
            ]))
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <cols>
            <col min="1" max="1" width="8" customWidth="1"/>
            <col min="2" max="2" width="28" customWidth="1"/>
            <col min="3" max="4" width="14" customWidth="1"/>
            <col min="5" max="5" width="30" customWidth="1"/>
            <col min="6" max="8" width="10" customWidth="1"/>
            <col min="9" max="10" width="42" customWidth="1"/>
          </cols>
          <sheetData>
            \(rows.joined(separator: "\n"))
          </sheetData>
        </worksheet>
        """
    }

    private enum CellValue {
        case blank
        case text(String)
        case number(Double)
    }

    private static let blank = CellValue.blank

    private static func text(_ value: String) -> CellValue {
        .text(value)
    }

    private static func number(_ value: Int) -> CellValue {
        .number(Double(value))
    }

    private static func number(_ value: Double) -> CellValue {
        .number(value)
    }

    private static func row(_ index: Int, _ values: [CellValue], style: Int = 0) -> String {
        let cells = values.enumerated().map { offset, value in
            cell(value, reference: "\(columnName(offset + 1))\(index)", style: style)
        }.joined()
        return #"<row r="\#(index)">\#(cells)</row>"#
    }

    private static func cell(_ value: CellValue, reference: String, style: Int) -> String {
        let styleAttribute = style > 0 ? #" s="\#(style)""# : ""
        switch value {
        case .blank:
            return #"<c r="\#(reference)"\#(styleAttribute)/>"#
        case .text(let text):
            return #"<c r="\#(reference)" t="inlineStr"\#(styleAttribute)><is><t>\#(xmlEscape(text))</t></is></c>"#
        case .number(let number):
            return #"<c r="\#(reference)"\#(styleAttribute)><v>\#(String(format: "%.4f", number))</v></c>"#
        }
    }

    private static func columnName(_ index: Int) -> String {
        var value = index
        var scalars: [UnicodeScalar] = []
        while value > 0 {
            let remainder = (value - 1) % 26
            scalars.insert(UnicodeScalar(65 + remainder)!, at: 0)
            value = (value - 1) / 26
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets>
        <sheet name="Hitomi Taster" sheetId="1" r:id="rId1"/>
      </sheets>
    </workbook>
    """

    private static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><name val="Aptos"/></font>
        <font><b/><sz val="11"/><name val="Aptos"/></font>
      </fonts>
      <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
      </fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="2">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>
      </cellXfs>
    </styleSheet>
    """
}
