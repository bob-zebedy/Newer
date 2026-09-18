import AppKit
import SwiftUI

struct TemplateSelectionCheckbox: NSViewRepresentable {
    let state: TemplateEntry.SelectionState
    let onToggle: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToggle: onToggle)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: "",
            target: context.coordinator,
            action: #selector(Coordinator.toggle)
        )
        button.allowsMixedState = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.onToggle = onToggle
        button.state = switch state {
        case .disabled:
            .off
        case .mixed:
            .mixed
        case .enabled:
            .on
        }
    }

    static func dismantleNSView(_ button: NSButton, coordinator _: Coordinator) {
        button.target = nil
        button.action = nil
    }

    final class Coordinator: NSObject {
        var onToggle: () -> Void

        init(onToggle: @escaping () -> Void) {
            self.onToggle = onToggle
        }

        @objc func toggle() {
            onToggle()
        }
    }
}
