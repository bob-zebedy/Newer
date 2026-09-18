indirect nonisolated enum TemplateEntry: Equatable, Sendable {
    case directory(path: String, name: String, children: [TemplateEntry])
    case template(TemplateItem)

    static func make(from templates: [TemplateItem]) -> [TemplateEntry] {
        let records = templates.compactMap { template -> TemplateEntryRecord? in
            guard let components = template.pathComponents else { return nil }
            return TemplateEntryRecord(template: template, remainingComponents: components)
        }
        return make(from: records, parentRelativePath: "")
    }

    private static func make(
        from records: [TemplateEntryRecord],
        parentRelativePath: String
    ) -> [TemplateEntry] {
        var entries: [TemplateEntry] = []
        var addedDirectories: Set<String> = []

        for record in records {
            guard let component = record.remainingComponents.first else { continue }
            if record.remainingComponents.count == 1 {
                entries.append(.template(record.template))
                continue
            }

            guard addedDirectories.insert(component).inserted else { continue }
            let children = records.compactMap { candidate -> TemplateEntryRecord? in
                guard candidate.remainingComponents.first == component else { return nil }
                return TemplateEntryRecord(
                    template: candidate.template,
                    remainingComponents: Array(candidate.remainingComponents.dropFirst())
                )
            }
            let path = parentRelativePath.isEmpty
                ? component
                : "\(parentRelativePath)/\(component)"
            entries.append(.directory(
                path: path,
                name: component,
                children: make(from: children, parentRelativePath: path)
            ))
        }

        return entries
    }
}

private nonisolated struct TemplateEntryRecord: Sendable {
    let template: TemplateItem
    let remainingComponents: [String]
}
