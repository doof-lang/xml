# std/xml

Parse and generate a practical, deliberately small XML document model without
native code.

## Usage

```doof
import { parseXml, stringifyXml } from "std/xml"

document := try parseXml("<book id=\"1\"><title>Doof &amp; XML</title></book>")
println(document.root.name)
println(document.root.childElements()[0].textContent())

encoded := try stringifyXml(document)
```

`parseXml` returns an `XmlDocument` whose root is an `XmlElement`. Element
children are `XmlElement`, `XmlText`, `XmlComment`, or `XmlCData` nodes.
Attributes preserve source order, `attribute` provides checked lookup,
`childElements` filters out non-element nodes, and `textContent` recursively
collects text and CDATA.

The parser supports XML declarations, nested and self-closing elements,
single- or double-quoted attributes, mixed content, comments, CDATA, and the
five predefined XML entities (`amp`, `lt`, `gt`, `quot`, and `apos`). Errors
include a kind, byte index, and one-based line and column.

This first cut is intentionally strict and does not yet support DOCTYPE,
custom entities, numeric character references, processing instructions, or
the full Unicode XML name grammar. Colons are accepted in names so namespace
qualified documents can be represented, but namespace URIs are not resolved.

`stringifyXml` escapes text and attributes and validates names, comments, and
CDATA. Empty elements use the `<name/>` form.

Tests can be run with `doof test xml`.

## Typed tags

Doof typed-tag syntax can construct strongly typed domain classes which then
lower themselves into the `XmlElement` model for serialization. See the
[`samples/typed-tags`](samples/typed-tags) SAML metadata example for enum-typed
bindings, nested identity-provider settings, namespace-qualified names,
serialization, and parsing the result back through `std/xml`.
