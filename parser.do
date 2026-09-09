import { StringBuilder } from "std/string"
import {
  decodeXmlText,
  isNameCharacter,
  isNameStart,
  isXmlWhitespace,
  matchesAt,
  normalizeXmlLineEndings,
  xmlFailure,
} from "./support"
import {
  isValidEncodingName,
  isValidXmlVersion,
  validateXmlCharacters,
} from "./validation"
import {
  XmlCData,
  XmlComment,
  XmlDeclaration,
  XmlDocument,
  XmlElement,
  XmlError,
  XmlErrorKind,
  XmlNode,
  XmlText,
} from "./types"

type ParsedAttributes = ReadonlyMap<string, string>

export function parseXml(text: string): Result<XmlDocument, XmlError> {
  return XmlParser { source: text }.parse()
}

class XmlParser {
  readonly source: string
  let index = 0
  let line = 1
  let column = 1

  parse(): Result<XmlDocument, XmlError> {
    try validateXmlCharacters(source)
    if source.length >= 3
      && int(source.charAt(0)) == 239
      && int(source.charAt(1)) == 187
      && int(source.charAt(2)) == 191 {
      advanceOne()
      advanceOne()
      advanceOne()
    }

    let declaration: XmlDeclaration | none = none
    if matchesAt(source, index, "<?xml") {
      try parsedDeclaration := parseDeclaration()
      declaration = parsedDeclaration
    }
    skipWhitespace()

    while matchesAt(source, index, "<!--") {
      try comment := parseComment()
      skipWhitespace()
    }

    if index >= source.length {
      return failure<XmlDocument>(.EmptyDocument, "XML document has no root element")
    }
    if source.charAt(index) != '<' {
      return failure<XmlDocument>(.InvalidSyntax, "Expected an XML root element")
    }

    try root := parseElement()
    skipWhitespace()
    while matchesAt(source, index, "<!--") {
      try comment := parseComment()
      skipWhitespace()
    }
    if index != source.length {
      kind: XmlErrorKind := if source.charAt(index) == '<' then .MultipleRoots else .InvalidSyntax
      return failure<XmlDocument>(kind, "Unexpected content after the root element")
    }
    return Success { value: XmlDocument { root, declaration } }
  }

  private parseDeclaration(): Result<XmlDeclaration, XmlError> {
    advanceText("<?xml")
    if index >= source.length || !isXmlWhitespace(source.charAt(index)) {
      return failure<XmlDeclaration>(.InvalidSyntax, "Expected whitespace after '<?xml'")
    }
    try attributes := parseAttributes("?>")
    if !matchesAt(source, index, "?>") {
      return failure<XmlDeclaration>(.UnexpectedEnd, "Unclosed XML declaration")
    }
    advanceText("?>")

    names := attributes.keys()
    if names.length == 0 || names[0] != "version" {
      return failure<XmlDeclaration>(.InvalidSyntax, "XML declaration requires a version")
    }
    version := attributes["version"]
    if !isValidXmlVersion(version) {
      return failure<XmlDeclaration>(.InvalidSyntax, "Unsupported XML version '${version}'")
    }
    let nameIndex = 1
    if nameIndex < names.length && names[nameIndex] == "encoding" { nameIndex += 1 }
    if nameIndex < names.length && names[nameIndex] == "standalone" { nameIndex += 1 }
    if nameIndex != names.length {
      return failure<XmlDeclaration>(
        .InvalidSyntax,
        "XML declaration attributes must appear in version, encoding, standalone order",
      )
    }
    encoding := try? attributes.get("encoding")
    if encoding != none && !isValidEncodingName(encoding!) {
      return failure<XmlDeclaration>(.InvalidSyntax, "Invalid XML encoding name")
    }
    standaloneText := try? attributes.get("standalone")
    let standalone: bool | none = none
    if standaloneText != none {
      if standaloneText! == "yes" { standalone = true }
      else if standaloneText! == "no" { standalone = false }
      else {
        return failure<XmlDeclaration>(.InvalidSyntax, "standalone must be 'yes' or 'no'")
      }
    }
    return Success { value: XmlDeclaration { version, encoding, standalone } }
  }

  private parseElement(): Result<XmlElement, XmlError> {
    advanceText("<")
    if index >= source.length {
      return failure<XmlElement>(.UnexpectedEnd, "Expected an element name")
    }
    if source.charAt(index) == '!' || source.charAt(index) == '?' || source.charAt(index) == '/' {
      return failure<XmlElement>(.UnsupportedMarkup, "Expected an element start tag")
    }
    try name := parseName()
    try attributes := parseAttributes(">")

    if matchesAt(source, index, "/>") {
      advanceText("/>")
      return Success {
        value: XmlElement { name, attributes, children: readonly [] }
      }
    }
    if !matchesAt(source, index, ">") {
      return failure<XmlElement>(.UnexpectedEnd, "Unclosed start tag '<${name}>'")
    }
    advanceText(">")

    children: XmlNode[] := []
    while index < source.length {
      if matchesAt(source, index, "</") {
        advanceText("</")
        try closingName := parseName()
        skipWhitespace()
        if !matchesAt(source, index, ">") {
          return failure<XmlElement>(.InvalidSyntax, "Expected '>' after closing tag")
        }
        advanceText(">")
        if closingName != name {
          return failure<XmlElement>(
            .MismatchedTag,
            "Closing tag '</${closingName}>' does not match '<${name}>'",
          )
        }
        return Success {
          value: XmlElement { name, attributes, children: children.drainToReadonly() }
        }
      }
      if matchesAt(source, index, "<!--") {
        try comment := parseComment()
        children.push(comment)
        continue
      }
      if matchesAt(source, index, "<![CDATA[") {
        try cdata := parseCData()
        children.push(cdata)
        continue
      }
      if matchesAt(source, index, "<!") || matchesAt(source, index, "<?") {
        return failure<XmlElement>(
          .UnsupportedMarkup,
          "DOCTYPE, processing instructions, and other declarations are not supported",
        )
      }
      if source.charAt(index) == '<' {
        try child := parseElement()
        children.push(child)
        continue
      }
      try text := parseText()
      if text.value != "" {
        children.push(text)
      }
    }
    return failure<XmlElement>(.UnexpectedEnd, "Element '<${name}>' is not closed")
  }

  private parseAttributes(terminator: string): Result<ParsedAttributes, XmlError> {
    attributes: Map<string, string> := {}
    while index < source.length {
      whitespaceStart := index
      skipWhitespace()
      if matchesAt(source, index, terminator) || matchesAt(source, index, "/>") {
        return Success { value: attributes.drainToReadonly() }
      }
      if index == whitespaceStart {
        return failure<ParsedAttributes>(.InvalidSyntax, "Expected whitespace before attribute")
      }
      try name := parseName()
      if attributes.has(name) {
        return failure<ParsedAttributes>(
          .DuplicateAttribute, "Duplicate attribute '${name}'",
        )
      }
      skipWhitespace()
      if !matchesAt(source, index, "=") {
        return failure<ParsedAttributes>(.InvalidSyntax, "Expected '=' after '${name}'")
      }
      advanceText("=")
      skipWhitespace()
      if index >= source.length || (source.charAt(index) != '\"' && source.charAt(index) != '\'') {
        return failure<ParsedAttributes>(.InvalidSyntax, "Expected a quoted attribute value")
      }
      quote := source.charAt(index)
      advanceOne()
      valueStart := index
      valueLine := line
      valueColumn := column
      while index < source.length && source.charAt(index) != quote {
        if source.charAt(index) == '<' {
          return failure<ParsedAttributes>(.InvalidSyntax, "Attribute values cannot contain '<'")
        }
        advanceOne()
      }
      if index >= source.length {
        return failure<ParsedAttributes>(.UnexpectedEnd, "Unclosed attribute value")
      }
      raw := source.substring(valueStart, index)
      try value := decodeXmlText(raw, valueStart, valueLine, valueColumn, true)
      advanceOne()
      attributes.set(name, value)
    }
    return failure<ParsedAttributes>(.UnexpectedEnd, "Unclosed tag")
  }

  private parseName(): Result<string, XmlError> {
    start := index
    if index >= source.length || !isNameStart(source.charAt(index)) {
      return failure<string>(.InvalidName, "Expected an XML name")
    }
    advanceOne()
    while index < source.length && isNameCharacter(source.charAt(index)) {
      advanceOne()
    }
    return Success { value: source.substring(start, index) }
  }

  private parseText(): Result<XmlText, XmlError> {
    start := index
    startLine := line
    startColumn := column
    while index < source.length && source.charAt(index) != '<' {
      if matchesAt(source, index, "]]>") {
        return failure<XmlText>(.InvalidSyntax, "']]>' is only valid as a CDATA terminator")
      }
      advanceOne()
    }
    raw := source.substring(start, index)
    try value := decodeXmlText(raw, start, startLine, startColumn, false)
    return Success { value: XmlText { value } }
  }

  private parseComment(): Result<XmlComment, XmlError> {
    advanceText("<!--")
    start := index
    while index < source.length && !matchesAt(source, index, "-->") {
      if matchesAt(source, index, "--") {
        return failure<XmlComment>(.InvalidSyntax, "XML comments cannot contain '--'")
      }
      advanceOne()
    }
    if index >= source.length {
      return failure<XmlComment>(.UnexpectedEnd, "Unclosed XML comment")
    }
    value := normalizeXmlLineEndings(source.substring(start, index))
    advanceText("-->")
    return Success { value: XmlComment { value } }
  }

  private parseCData(): Result<XmlCData, XmlError> {
    advanceText("<![CDATA[")
    start := index
    while index < source.length && !matchesAt(source, index, "]]>") {
      advanceOne()
    }
    if index >= source.length {
      return failure<XmlCData>(.UnexpectedEnd, "Unclosed CDATA section")
    }
    value := normalizeXmlLineEndings(source.substring(start, index))
    advanceText("]]>")
    return Success { value: XmlCData { value } }
  }

  private skipWhitespace(): none {
    while index < source.length && isXmlWhitespace(source.charAt(index)) {
      advanceOne()
    }
  }

  private advanceText(value: string): none {
    for _ of 0..<value.length {
      advanceOne()
    }
  }

  private advanceOne(): none {
    current := source.charAt(index)
    if current == '\r' && index + 1 < source.length && source.charAt(index + 1) == '\n' {
      index += 2
      line += 1
      column = 1
    } else if current == '\n' || current == '\r' {
      index += 1
      line += 1
      column = 1
    } else {
      index += 1
      column += 1
    }
  }

  private failure<T>(kind: XmlErrorKind, message: string): Result<T, XmlError> {
    return xmlFailure<T>(kind, index, line, column, message)
  }
}
