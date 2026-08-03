import AppKit
import Foundation

struct ImageConversionDialogRequest: Equatable {
    var formats: [ImageConversionFormat]
    var preferredFormat: ImageConversionFormat
    var initialQuality: Int
    var language: AppInterfaceLanguage
}

struct ImageConversionDialogSelection: Equatable {
    var format: ImageConversionFormat
    var quality: Int
}

@MainActor
final class ImageConversionDialogService {
    typealias Handler =
        (ImageConversionDialogRequest) ->
            ImageConversionDialogSelection?

    private let handler: Handler?

    init(handler: Handler? = nil) {
        self.handler = handler
    }

    func chooseConversion(
        _ request: ImageConversionDialogRequest
    ) -> ImageConversionDialogSelection? {
        if let handler {
            return handler(request)
        }
        guard !request.formats.isEmpty else {
            return nil
        }

        let formatPopup =
            NSPopUpButton(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 220,
                        height: 26
                    ),
                pullsDown: false
            )
        formatPopup.addItems(
            withTitles:
                request.formats.map(\.label)
        )
        if let selectedIndex =
            request.formats.firstIndex(
                of: request.preferredFormat
            ) {
            formatPopup.selectItem(
                at: selectedIndex
            )
        }

        let qualitySlider =
            NSSlider(
                value:
                    Double(request.initialQuality),
                minValue: 1,
                maxValue: 100,
                target: nil,
                action: nil
            )
        qualitySlider.numberOfTickMarks = 5
        qualitySlider.allowsTickMarkValuesOnly =
            false
        let qualityTitle =
            AppLocalization.text(
                "JPEG Quality",
                language: request.language
            )
        qualitySlider.toolTip = qualityTitle
        qualitySlider.setAccessibilityLabel(
            qualityTitle
        )

        let form =
            NSGridView(
                views: [
                    [
                        NSTextField(
                            labelWithString:
                                AppLocalization
                                .text(
                                    "File Format",
                                    language:
                                        request.language
                                )
                        ),
                        formatPopup
                    ],
                    [
                        NSTextField(
                            labelWithString:
                                qualityTitle
                        ),
                        qualitySlider
                    ]
                ]
            )
        form.column(at: 0).xPlacement =
            .trailing
        form.column(at: 1).xPlacement =
            .fill
        form.rowSpacing = 8
        form.columnSpacing = 10
        form.frame =
            NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: 62
            )

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText =
            AppLocalization.text(
                "Convert Image Format",
                language: request.language
            )
        alert.informativeText =
            AppLocalization.text(
                "Convert image files from the selected completed tasks.",
                language: request.language
            )
        alert.accessoryView = form
        alert.addButton(
            withTitle:
                AppLocalization.text(
                    "Convert",
                    language: request.language
                )
        )
        alert.addButton(
            withTitle:
                AppLocalization.text(
                    "Cancel",
                    language: request.language
                )
        )
        guard alert.runModal() ==
            .alertFirstButtonReturn else {
            return nil
        }

        let selectedIndex =
            max(
                0,
                min(
                    formatPopup
                        .indexOfSelectedItem,
                    request.formats.count - 1
                )
            )
        return ImageConversionDialogSelection(
            format:
                request.formats[selectedIndex],
            quality: qualitySlider.integerValue
        )
    }
}
