import SakuraCordModels

extension ProfileEditorState {
    func updatePersonalWidget(id: String, _ update: (inout ProfilePersonalWidget) -> Void) {
        guard canEditPersonalWidget, var widget = widgets.first(where: { $0.id == id }), case var .personal(personal) = widget.content else { return }
        update(&personal)
        widget.content = .personal(personal)
        updateWidget(widget)
    }

    func updateWidgetCover(id: String, section: Int, _ update: (inout ProfileWidgetCover) -> Void) {
        updatePersonalWidget(id: id) { personal in
            guard personal.sections.indices.contains(section), case var .cover(cover) = personal.sections[section] else { return }
            update(&cover); personal.sections[section] = .cover(cover)
        }
    }

    func updateWidgetField(id: String, section: Int, fieldID: ProfileWidgetField.ID, _ update: (inout ProfileWidgetField) -> Void) {
        updatePersonalWidget(id: id) { personal in
            guard personal.sections.indices.contains(section), case var .fields(fields) = personal.sections[section],
                  let index = fields.firstIndex(where: { $0.id == fieldID }) else { return }
            update(&fields[index]); personal.sections[section] = .fields(fields)
        }
    }

    func removeWidgetField(id: String, section: Int, fieldID: ProfileWidgetField.ID) {
        updatePersonalWidget(id: id) { personal in
            guard personal.sections.indices.contains(section), case let .fields(fields) = personal.sections[section] else { return }
            personal.sections[section] = .fields(fields.filter { $0.id != fieldID })
        }
    }

    func addWidgetFields(id: String, section: Int, count: Int) {
        updatePersonalWidget(id: id) { personal in
            guard personal.sections.indices.contains(section), case var .fields(fields) = personal.sections[section],
                  count > 0, fields.count + count <= 4 else { return }
            fields.append(contentsOf: (0 ..< count).map { _ in ProfileWidgetField() })
            personal.sections[section] = .fields(fields)
        }
    }
}
