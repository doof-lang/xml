import {
  XmlDeclaration,
  XmlDocument,
  XmlElement,
  XmlNode,
  XmlText,
  parseXml,
  stringifyXml,
} from "std/xml"

enum SamlBinding {
  HttpRedirect,
  HttpPost,
}

enum NameIdKind {
  EmailAddress,
  Persistent,
}

class SingleSignOnService {
  binding: SamlBinding
  location: string

  toXmlElement(): XmlElement {
    return XmlElement {
      name: "md:SingleSignOnService",
      attributes: { "Binding": bindingUri(binding), "Location": location },
      children: readonly [],
    }
  }
}

class NameIdFormat {
  kind: NameIdKind

  toXmlElement(): XmlElement {
    return XmlElement {
      name: "md:NameIDFormat",
      attributes: {},
      children: [XmlText { value: nameIdUri(kind) }],
    }
  }
}

type IdentityProviderSetting = SingleSignOnService | NameIdFormat

class IdentityProvider {
  wantAuthnRequestsSigned: bool = false
  children: IdentityProviderSetting[] = []

  toXmlElement(): XmlElement {
    settings: XmlNode[] := []
    for child of children {
      case child {
        service: SingleSignOnService -> settings.push(service.toXmlElement())
        format: NameIdFormat -> settings.push(format.toXmlElement())
      }
    }
    return XmlElement {
      name: "md:IDPSSODescriptor",
      attributes: {
        "protocolSupportEnumeration": "urn:oasis:names:tc:SAML:2.0:protocol",
        "WantAuthnRequestsSigned": if wantAuthnRequestsSigned then "true" else "false",
      },
      children: settings.drainToReadonly(),
    }
  }
}

class EntityDescriptor {
  entityId: string
  children: IdentityProvider[] = []

  toXmlDocument(): XmlDocument {
    roles: XmlNode[] := []
    for identityProvider of children {
      roles.push(identityProvider.toXmlElement())
    }
    return XmlDocument {
      declaration: XmlDeclaration { version: "1.0", encoding: "UTF-8" },
      root: XmlElement {
        name: "md:EntityDescriptor",
        attributes: {
          "xmlns:md": "urn:oasis:names:tc:SAML:2.0:metadata",
          "entityID": entityId,
        },
        children: roles.drainToReadonly(),
      },
    }
  }
}

function bindingUri(binding: SamlBinding): string {
  return case binding {
    .HttpRedirect -> "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect",
    .HttpPost -> "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST",
  }
}

function nameIdUri(kind: NameIdKind): string {
  return case kind {
    .EmailAddress -> "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
    .Persistent -> "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent",
  }
}

function main(): int {
  metadata := <EntityDescriptor entityId="https://identity.example.com/saml">
    <IdentityProvider wantAuthnRequestsSigned=true>
      <SingleSignOnService
        binding={SamlBinding.HttpRedirect}
        location="https://identity.example.com/saml/sso/redirect"
      />
      <SingleSignOnService
        binding={SamlBinding.HttpPost}
        location="https://identity.example.com/saml/sso/post"
      />
      <NameIdFormat kind={NameIdKind.EmailAddress}/>
      <NameIdFormat kind={NameIdKind.Persistent}/>
    </IdentityProvider>
  </EntityDescriptor>

  encoded := stringifyXml(metadata.toXmlDocument()) else error {
    println("Could not serialize XML: ${error.message}")
    return 1
  }
  println(encoded)

  decoded := parseXml(encoded) else error {
    println("Could not parse serialized XML: ${error.message}")
    return 1
  }
  descriptor := decoded.root.childElements()[0]
  println("Parsed ${descriptor.childElements().length} SAML identity-provider settings")
  return 0
}
