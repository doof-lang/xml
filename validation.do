import { XmlError, XmlErrorKind } from "./types"

export function isValidXmlVersion(value: string): bool {
  return value == "1.0" || value == "1.1"
}

export function isValidEncodingName(value: string): bool {
  if value.length == 0 || !isAsciiLetter(value.charAt(0)) { return false }
  for index of 1..<value.length {
    character := value.charAt(index)
    if !isAsciiLetter(character)
      && !(character >= '0' && character <= '9')
      && character != '.' && character != '_' && character != '-' {
      return false
    }
  }
  return true
}

export function validateXmlCharacters(value: string): Result<none, XmlError> {
  let index = 0
  let line = 1
  let column = 1
  while index < value.length {
    first := int(value.charAt(index))
    let codepoint = first
    let width = 1

    if first >= 194 && first <= 223 && index + 1 < value.length {
      second := int(value.charAt(index + 1))
      if isContinuation(second) {
        codepoint = (first - 192) * 64 + second - 128
        width = 2
      } else {
        return invalidXmlCharacter<none>(index, line, column)
      }
    } else if first >= 224 && first <= 239 && index + 2 < value.length {
      second := int(value.charAt(index + 1))
      third := int(value.charAt(index + 2))
      validSecond := isContinuation(second)
        && (first != 224 || second >= 160)
        && (first != 237 || second <= 159)
      if validSecond && isContinuation(third) {
        codepoint = (first - 224) * 4096 + (second - 128) * 64 + third - 128
        width = 3
      } else {
        return invalidXmlCharacter<none>(index, line, column)
      }
    } else if first >= 240 && first <= 244 && index + 3 < value.length {
      second := int(value.charAt(index + 1))
      third := int(value.charAt(index + 2))
      fourth := int(value.charAt(index + 3))
      validSecond := isContinuation(second)
        && (first != 240 || second >= 144)
        && (first != 244 || second <= 143)
      if validSecond && isContinuation(third) && isContinuation(fourth) {
        codepoint = (first - 240) * 262144 + (second - 128) * 4096
          + (third - 128) * 64 + fourth - 128
        width = 4
      } else {
        return invalidXmlCharacter<none>(index, line, column)
      }
    } else if first >= 128 {
      return invalidXmlCharacter<none>(index, line, column)
    }

    if !isXmlCharacter(codepoint) {
      return invalidXmlCharacter<none>(index, line, column)
    }
    if first == 13 {
      if index + 1 < value.length && value.charAt(index + 1) == '\n' { width = 2 }
      line += 1
      column = 1
    } else if first == 10 {
      line += 1
      column = 1
    } else {
      column += width
    }
    index += width
  }
  return Success()
}

function isAsciiLetter(character: char): bool {
  return (character >= 'A' && character <= 'Z')
    || (character >= 'a' && character <= 'z')
}

function isContinuation(value: int): bool => value >= 128 && value <= 191

function isXmlCharacter(value: int): bool {
  return value == 9 || value == 10 || value == 13
    || (value >= 32 && value <= 55295)
    || (value >= 57344 && value <= 65533)
    || (value >= 65536 && value <= 1114111)
}

function invalidXmlCharacter<T>(
  index: int,
  line: int,
  column: int,
): Result<T, XmlError> {
  return Failure {
    error: XmlError {
      kind: XmlErrorKind.InvalidSyntax,
      index,
      line,
      column,
      message: "XML contains an invalid character or UTF-8 sequence",
    }
  }
}
