import { StringBuilder } from "std/string"
import { XmlError, XmlErrorKind } from "./types"

export function xmlFailure<T>(
  kind: XmlErrorKind,
  index: int,
  line: int,
  column: int,
  message: string,
): Result<T, XmlError> {
  return Failure { error: XmlError { kind, index, line, column, message } }
}

export function matchesAt(value: string, index: int, expected: string): bool {
  return index >= 0
    && index + expected.length <= value.length
    && value.substring(index, index + expected.length) == expected
}

export function isXmlWhitespace(character: char): bool {
  return character == ' ' || character == '\t' || character == '\r' || character == '\n'
}

export function isNameStart(character: char): bool {
  return character == ':' || character == '_'
    || (character >= 'A' && character <= 'Z')
    || (character >= 'a' && character <= 'z')
}

export function isNameCharacter(character: char): bool {
  return isNameStart(character)
    || (character >= '0' && character <= '9')
    || character == '-' || character == '.'
}

export function normalizeXmlLineEndings(value: string): string {
  output := StringBuilder()
  let index = 0
  while index < value.length {
    current := value.charAt(index)
    if current == '\r' {
      output.append("\n")
      if index + 1 < value.length && value.charAt(index + 1) == '\n' {
        index += 2
      } else {
        index += 1
      }
    } else {
      output.append(value.substring(index, index + 1))
      index += 1
    }
  }
  return output.drainToString()
}

export function decodeXmlText(
  raw: string,
  baseIndex: int,
  baseLine: int,
  baseColumn: int,
  attribute: bool,
): Result<string, XmlError> {
  output := StringBuilder()
  let index = 0
  let line = baseLine
  let column = baseColumn
  while index < raw.length {
    current := raw.charAt(index)
    if current != '&' {
      if current == '\r' {
        output.append(if attribute then " " else "\n")
        if index + 1 < raw.length && raw.charAt(index + 1) == '\n' {
          index += 2
        } else {
          index += 1
        }
        line += 1
        column = 1
      } else if current == '\n' {
        output.append(if attribute then " " else "\n")
        index += 1
        line += 1
        column = 1
      } else {
        if attribute && current == '\t' {
          output.append(" ")
        } else {
          output.append(raw.substring(index, index + 1))
        }
        index += 1
        column += 1
      }
      continue
    }

    let end = index + 1
    while end < raw.length && raw.charAt(end) != ';' {
      if raw.charAt(end) == '&' || raw.charAt(end) == '<' || end - index > 16 {
        return xmlFailure<string>(
          .InvalidEntity, baseIndex + index, line, column,
          "Invalid XML entity reference",
        )
      }
      end += 1
    }
    if end >= raw.length {
      return xmlFailure<string>(
        .InvalidEntity, baseIndex + index, line, column,
        "Unclosed XML entity reference",
      )
    }

    entity := raw.substring(index + 1, end)
    if entity == "amp" { output.append("&") }
    else if entity == "lt" { output.append("<") }
    else if entity == "gt" { output.append(">") }
    else if entity == "quot" { output.append("\"") }
    else if entity == "apos" { output.append("'") }
    else {
      return xmlFailure<string>(
        .InvalidEntity, baseIndex + index, line, column,
        "Unsupported XML entity '&${entity};'",
      )
    }
    column += end - index + 1
    index = end + 1
  }
  return Success { value: output.drainToString() }
}
