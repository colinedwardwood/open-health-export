// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import MQTTCodec
import RequestTemplate

/// MQTT topics may be AR-21 templates. Wildcards stay forbidden after render.
public enum MQTTTopicTemplate {
    public static func render(_ template: String, values: [String: String]) throws -> String {
        let rendered: String
        if template.contains("{{") {
            rendered = try RequestTemplate(template).render(context: TemplateContext(values: values))
        } else {
            rendered = template
        }
        try MQTTTopic.validate(rendered)
        return rendered
    }
}
