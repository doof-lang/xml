import { Assert } from "std/assert"
import {
  XmlCData,
  XmlComment,
  XmlDeclaration,
  XmlDocument,
  XmlElement,
  XmlError,
  XmlErrorKind,
  XmlText,
  parseXml,
  stringifyXml,
} from "./index"

function assertParseFailure(text: string, kind: XmlErrorKind): XmlError {
  case parseXml(text) {
    failure: Failure -> {
      Assert.equal(failure.error.kind, kind)
      return failure.error
    }
    _: Success -> Assert.fail("expected XML parsing to fail")
  }
  panic("unreachable")
}

function assertStringifyFailure(document: XmlDocument, kind: XmlErrorKind): XmlError {
  case stringifyXml(document) {
    failure: Failure -> {
      Assert.equal(failure.error.kind, kind)
      return failure.error
    }
    _: Success -> Assert.fail("expected XML serialization to fail")
  }
  panic("unreachable")
}

export function testParsesElementsAttributesAndText(): none {
  document := parseXml("<catalog lang='en'><book id=\"1\">Doof &amp; XML</book><empty/></catalog>")!
  Assert.equal(document.root.name, "catalog")
  Assert.equal(document.root.attribute("lang")!, "en")
  children := document.root.childElements()
  Assert.equal(children.length, 2)
  Assert.equal(children[0].name, "book")
  Assert.equal(children[0].attribute("id")!, "1")
  Assert.equal(children[0].textContent(), "Doof & XML")
  Assert.equal(children[1].name, "empty")
}

export function testParsesDeclarationCommentsAndCData(): none {
  document := parseXml("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><root><!-- note --><![CDATA[a < b && c > d]]></root>")!
  Assert.equal(document.declaration!.version, "1.0")
  Assert.equal(document.declaration!.encoding!, "UTF-8")
  Assert.equal(document.declaration!.standalone!, true)
  Assert.equal(document.root.children.length, 2)
  case document.root.children[0] {
    comment: XmlComment -> Assert.equal(comment.value, " note ")
    _ -> Assert.fail("expected a comment")
  }
  case document.root.children[1] {
    cdata: XmlCData -> Assert.equal(cdata.value, "a < b && c > d")
    _ -> Assert.fail("expected CDATA")
  }
  Assert.equal(document.root.textContent(), "a < b && c > d")
}

export function testPreservesMixedContent(): none {
  document := parseXml("<p>Hello <strong>XML</strong>!</p>")!
  root := document.root
  Assert.equal(root.children.length, 3)
  Assert.equal(root.textContent(), "Hello XML!")
}

export function testRejectsMalformedDocuments(): none {
  mismatch := assertParseFailure("<one><two/></three>", .MismatchedTag)
  Assert.equal(mismatch.line, 1)

  assertParseFailure("<root a=\"1\" a=\"2\"/>", .DuplicateAttribute)
  assertParseFailure("<root>&unknown;</root>", .InvalidEntity)
  assertParseFailure("<one/><two/>", .MultipleRoots)
  assertParseFailure("<!DOCTYPE root><root/>", .UnsupportedMarkup)
  assertParseFailure("", .EmptyDocument)
}

export function testStringifiesAndRoundTrips(): none {
  document := XmlDocument {
    root: XmlElement {
      name: "message",
      attributes: { "kind": "greeting & farewell" },
      children: [
        XmlText { value: "Hello <world>" },
        XmlComment { value: " safe " },
        XmlCData { value: "raw <text>" },
      ],
    }
  }
  encoded := stringifyXml(document)!
  Assert.equal(encoded, "<message kind=\"greeting &amp; farewell\">Hello &lt;world&gt;<!-- safe --><![CDATA[raw <text>]]></message>")
  decoded := parseXml(encoded)!
  Assert.equal(decoded.root.textContent(), "Hello <world>raw <text>")
}

export function testNormalizesLineEndingsAndAttributeWhitespace(): none {
  document := parseXml(
    "<root value=\"a\tb\r\nc\rd\">x\r\ny\rz<![CDATA[c\r\nd]]><!--e\rf--></root>",
  )!
  Assert.equal(document.root.attribute("value")!, "a b c d")
  Assert.equal(document.root.textContent(), "x\ny\nzc\nd")
  case document.root.children[1] {
    cdata: XmlCData -> Assert.equal(cdata.value, "c\nd")
    _ -> Assert.fail("expected normalized CDATA")
  }
  case document.root.children[2] {
    comment: XmlComment -> Assert.equal(comment.value, "e\nf")
    _ -> Assert.fail("expected normalized comment")
  }

  error := assertParseFailure("<root>\r\n&unknown;</root>", .InvalidEntity)
  Assert.equal(error.line, 2)
  Assert.equal(error.column, 1)
}

export function testRequiresWhitespaceBeforeAttributes(): none {
  assertParseFailure("<root first=\"1\"second=\"2\"/>", .InvalidSyntax)
  assertParseFailure("<?xml version=\"1.0\"encoding=\"UTF-8\"?><root/>", .InvalidSyntax)
}

export function testEnforcesDeclarationPlacementAndOrder(): none {
  assertParseFailure(" <?xml version=\"1.0\"?><root/>", .UnsupportedMarkup)
  assertParseFailure(
    "<?xml encoding=\"UTF-8\" version=\"1.0\"?><root/>",
    .InvalidSyntax,
  )
  assertParseFailure(
    "<?xml version=\"1.0\" standalone=\"yes\" encoding=\"UTF-8\"?><root/>",
    .InvalidSyntax,
  )
  assertParseFailure("<?xml version=\"1.0\" encoding=\"not valid\"?><root/>", .InvalidSyntax)
}

export function testRejectsInvalidXmlCharacters(): none {
  parseError := assertParseFailure("<root>\0</root>", .InvalidSyntax)
  Assert.equal(parseError.index, 6)

  assertStringifyFailure(
    XmlDocument {
      root: XmlElement {
        name: "root",
        attributes: {},
        children: [XmlText { value: "bad \0" }],
      }
    },
    .InvalidSyntax,
  )
  assertStringifyFailure(
    XmlDocument {
      root: XmlElement {
        name: "root",
        attributes: { "value": "bad \0" },
        children: readonly [],
      }
    },
    .InvalidSyntax,
  )
  assertStringifyFailure(
    XmlDocument {
      root: XmlElement {
        name: "root",
        attributes: {},
        children: [XmlComment { value: "bad \0" }],
      }
    },
    .InvalidSyntax,
  )
  assertStringifyFailure(
    XmlDocument {
      root: XmlElement {
        name: "root",
        attributes: {},
        children: [XmlCData { value: "bad \0" }],
      }
    },
    .InvalidSyntax,
  )
}

export function testValidatesSerializedDeclarations(): none {
  root := XmlElement { name: "root", attributes: {}, children: readonly [] }
  assertStringifyFailure(
    XmlDocument {
      root,
      declaration: XmlDeclaration { version: "1.0\"?><evil/>" },
    },
    .InvalidSyntax,
  )
  assertStringifyFailure(
    XmlDocument {
      root,
      declaration: XmlDeclaration { version: "1.0", encoding: "UTF-8\"?><evil/>" },
    },
    .InvalidSyntax,
  )
}

export function testAcceptsValidUtf8Characters(): none {
  document := parseXml("<root>hé 😀</root>")!
  Assert.equal(document.root.textContent(), "hé 😀")
  Assert.equal(stringifyXml(document)!, "<root>hé 😀</root>")

  // The first character in this fixture is a UTF-8 byte-order mark.
  withBom := parseXml("﻿<root/>")!
  Assert.equal(withBom.root.name, "root")
}
