import { StringBuilder } from "std/string"

export enum XmlErrorKind {
  EmptyDocument,
  InvalidSyntax,
  InvalidName,
  InvalidEntity,
  DuplicateAttribute,
  MismatchedTag,
  UnexpectedEnd,
  UnsupportedMarkup,
  MultipleRoots,
}

export class XmlError {
  readonly kind: XmlErrorKind
  readonly index: int
  readonly line: int
  readonly column: int
  readonly message: string
}

export class XmlDeclaration {
  readonly version: string
  readonly encoding: string | none = none
  readonly standalone: bool | none = none
}

export class XmlText {
  readonly value: string
}

export class XmlComment {
  readonly value: string
}

export class XmlCData {
  readonly value: string
}

export class XmlElement {
  readonly name: string
  readonly attributes: ReadonlyMap<string, string>
  readonly children: readonly XmlNode[]

  attribute(name: string): Result<string, string> => attributes.get(name)

  textContent(): string {
    output := StringBuilder()
    appendTextContent(children, output)
    return output.drainToString()
  }

  childElements(): readonly XmlElement[] {
    elements: XmlElement[] := []
    for child of children {
      case child {
        element: XmlElement -> elements.push(element)
        _ -> {}
      }
    }
    return elements.drainToReadonly()
  }
}

export type XmlNode = XmlElement | XmlText | XmlComment | XmlCData

export class XmlDocument {
  readonly root: XmlElement
  readonly declaration: XmlDeclaration | none = none
}

function appendTextContent(nodes: readonly XmlNode[], output: StringBuilder): none {
  for node of nodes {
    case node {
      text: XmlText -> output.append(text.value)
      cdata: XmlCData -> output.append(cdata.value)
      element: XmlElement -> appendTextContent(element.children, output)
      _: XmlComment -> {}
    }
  }
}
