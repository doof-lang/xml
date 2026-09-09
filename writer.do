import { StringBuilder } from "std/string"
import {
  isNameCharacter,
  isNameStart,
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
  XmlDocument,
  XmlElement,
  XmlError,
  XmlNode,
  XmlText,
} from "./types"

export function stringifyXml(document: XmlDocument): Result<string, XmlError> {
  output := StringBuilder()
  declaration := document.declaration
  if declaration != none {
    value := declaration!
    if !isValidXmlVersion(value.version) {
      return xmlFailure<string>(.InvalidSyntax, 0, 1, 1, "Invalid XML declaration version")
    }
    if value.encoding != none && !isValidEncodingName(value.encoding!) {
      return xmlFailure<string>(.InvalidSyntax, 0, 1, 1, "Invalid XML encoding name")
    }
    output.append("<?xml version=\"")
    output.append(value.version)
    output.append("\"")
    if value.encoding != none {
      output.append(" encoding=\"")
      output.append(value.encoding!)
      output.append("\"")
    }
    if value.standalone != none {
      output.append(" standalone=\"")
      output.append(if value.standalone! then "yes" else "no")
      output.append("\"")
    }
    output.append("?>")
  }
  try appendElement(output, document.root)
  return Success { value: output.drainToString() }
}

function appendElement(output: StringBuilder, element: XmlElement): Result<none, XmlError> {
  if !validName(element.name) {
    return xmlFailure<none>(.InvalidName, 0, 1, 1, "Invalid element name '${element.name}'")
  }
  output.append("<")
  output.append(element.name)
  for name of element.attributes.keys() {
    if !validName(name) {
      return xmlFailure<none>(.InvalidName, 0, 1, 1, "Invalid attribute name '${name}'")
    }
    output.append(" ")
    output.append(name)
    output.append("=\"")
    try appendEscaped(output, element.attributes[name], true)
    output.append("\"")
  }
  if element.children.length == 0 {
    output.append("/>")
    return Success()
  }
  output.append(">")
  for child of element.children {
    try appendNode(output, child)
  }
  output.append("</")
  output.append(element.name)
  output.append(">")
  return Success()
}

function appendNode(output: StringBuilder, node: XmlNode): Result<none, XmlError> {
  case node {
    element: XmlElement -> return appendElement(output, element)
    text: XmlText -> {
      try appendEscaped(output, text.value, false)
      return Success()
    }
    comment: XmlComment -> {
      try validateXmlCharacters(comment.value)
      if comment.value.indexOf("--") >= 0 || comment.value.endsWith("-") {
        return xmlFailure<none>(.InvalidSyntax, 0, 1, 1, "Invalid XML comment")
      }
      output.append("<!--")
      output.append(comment.value)
      output.append("-->")
      return Success()
    }
    cdata: XmlCData -> {
      try validateXmlCharacters(cdata.value)
      if cdata.value.indexOf("]]>") >= 0 {
        return xmlFailure<none>(.InvalidSyntax, 0, 1, 1, "CDATA cannot contain ']]>'")
      }
      output.append("<![CDATA[")
      output.append(cdata.value)
      output.append("]]>")
      return Success()
    }
  }
}

function appendEscaped(
  output: StringBuilder,
  value: string,
  attribute: bool,
): Result<none, XmlError> {
  try validateXmlCharacters(value)
  let index = 0
  while index < value.length {
    current := value.charAt(index)
    if current == '&' { output.append("&amp;") }
    else if current == '<' { output.append("&lt;") }
    else if current == '>' { output.append("&gt;") }
    else if attribute && current == '\"' { output.append("&quot;") }
    else { output.append(value.substring(index, index + 1)) }
    index += 1
  }
  return Success()
}

function validName(value: string): bool {
  if value.length == 0 || !isNameStart(value.charAt(0)) { return false }
  for index of 1..<value.length {
    if !isNameCharacter(value.charAt(index)) { return false }
  }
  return true
}
