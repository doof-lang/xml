# std/xml API

## Functions

- `parseXml(text: string): Result<XmlDocument, XmlError>`
- `stringifyXml(document: XmlDocument): Result<string, XmlError>`

## Document model

- `XmlDocument { root, declaration }`
- `XmlDeclaration { version, encoding, standalone }`
- `XmlElement { name, attributes, children }`
- `XmlText { value }`
- `XmlComment { value }`
- `XmlCData { value }`
- `XmlNode = XmlElement | XmlText | XmlComment | XmlCData`

`XmlElement.attribute(name)` returns a `Result<string, string>`.
`XmlElement.childElements()` returns only element children.
`XmlElement.textContent()` recursively concatenates text and CDATA nodes.

## Errors

`XmlError` reports `kind`, zero-based byte `index`, and one-based `line` and
`column`. `XmlErrorKind` distinguishes empty documents, syntax and name
errors, invalid entities, duplicate attributes, mismatched tags, unexpected
end of input, unsupported markup, and multiple roots.
