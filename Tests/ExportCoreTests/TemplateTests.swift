import RequestTemplate
import TestSupport
import Testing

@Test func templateRequiresDirectiveAndClosedNames() throws {
    #expect(throws: TemplateError.missingDirective) {
        _ = try RequestTemplate("{{batchId}}").render(context: TemplateContext(values: ["batchId": "x"]))
    }
    #expect(throws: TemplateError.unknownDirective("exec")) {
        _ = try RequestTemplate("{{batchId|exec}}").render(context: TemplateContext(values: ["batchId": "x"]))
    }
    #expect(throws: TemplateError.unknownName("#if")) {
        _ = try RequestTemplate("{{#if|raw}}").render(context: TemplateContext())
    }
    #expect(throws: TemplateError.unclosedPlaceholder) {
        _ = try RequestTemplate("{{batchId|raw").render(context: TemplateContext(values: ["batchId": "x"]))
    }
}

@Test func templateJsonDirectiveCannotCloseAString() throws {
    let hostile = "\", \"admin\": true, \""
    let out = try RequestTemplate("{\"id\":{{batchId|json}}}").render(
        context: TemplateContext(values: ["batchId": hostile])
    )
    #expect(out == "{\"id\":\"\\\", \\\"admin\\\": true, \\\"\"}")
}

@Test func templateHeaderDirectiveRejectsCRLFInjection() {
    #expect(throws: TemplateError.headerInjection) {
        _ = try RequestTemplate("{{token|header}}").renderHeaderValue(
            context: TemplateContext(values: ["token": "ok\r\nX-Injected: 1"])
        )
    }
}

@Test func templateDoesNotProvidePathSlotsAndQueryEscapesSlash() throws {
    let out = try RequestTemplate("q={{batchId|query}}").render(
        context: TemplateContext(values: ["batchId": "../secret?x=1"])
    )
    #expect(!out.contains("../"))
    #expect(out.contains("%2F"))
    #expect(out.contains("%3F"))
}

@Test func templateSecretsAreHandlesAndCannotBeRaw() throws {
    let secrets = MemorySecrets(["ha_token": "s3cret"])
    let out = try RequestTemplate("Bearer {{secret:ha_token|header}}").renderHeaderValue(
        context: TemplateContext(secrets: secrets)
    )
    #expect(out == "Bearer s3cret")
    #expect(throws: TemplateError.rawForbidden("ha_token")) {
        _ = try RequestTemplate("{{secret:ha_token|raw}}").render(context: TemplateContext(secrets: secrets))
    }
}

@Test func templateUnknownTrustedNameFailsClosed() {
    #expect(throws: TemplateError.unknownName("metadata")) {
        _ = try RequestTemplate("{{metadata|json}}").render(context: TemplateContext())
    }
}
