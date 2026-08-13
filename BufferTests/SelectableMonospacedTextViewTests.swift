import AppKit
import SwiftUI
import XCTest

@testable import Buffer

@MainActor
final class SelectableMonospacedTextViewTests: XCTestCase {
    func testSwiftUIReusesAndResizesTextViewAcrossSelectionContentChanges() async throws {
        let model = TextSizingTestModel(text: "Short value")
        let hostingView = NSHostingView(
            rootView: TextSizingTestHarness(model: model)
                .frame(width: 240)
        )
        hostingView.layoutSubtreeIfNeeded()

        let textView = try XCTUnwrap(
            hostingView.firstDescendant(of: MeasuringSelectableTextView.self)
        )
        let singleLineHeight = textView.frame.height

        model.text = (1...80)
            .map { "Line \($0): a complete detail value" }
            .joined(separator: "\n")

        await eventually {
            hostingView.layoutSubtreeIfNeeded()
            return textView.frame.height > singleLineHeight * 70
        }

        XCTAssertTrue(
            hostingView.firstDescendant(of: MeasuringSelectableTextView.self) === textView,
            "The regression must exercise the reused AppKit view path"
        )
        XCTAssertEqual(
            textView.frame.height,
            textView.measuredHeight(constrainedTo: textView.frame.width),
            accuracy: 0.5
        )
    }

    func testReusedViewExpandsFromSingleLineToMultilineText() {
        let textView = makeTextView(width: 240)
        textView.setText("Short value")
        let singleLineHeight = textView.measuredHeight(constrainedTo: 240)

        textView.setText(
            (1...80)
                .map { "Line \($0): a complete detail value" }
                .joined(separator: "\n")
        )
        let multilineHeight = textView.measuredHeight(constrainedTo: 240)

        XCTAssertGreaterThan(multilineHeight, singleLineHeight * 70)
        XCTAssertEqual(textView.intrinsicContentSize.height, multilineHeight, accuracy: 0.5)
    }

    func testMeasurementReflowsWhenAvailableWidthChanges() {
        let textView = makeTextView(width: 360)
        textView.setText(
            Array(repeating: "width-sensitive text", count: 30)
                .joined(separator: " ")
        )

        let wideHeight = textView.measuredHeight(constrainedTo: 360)
        textView.setFrameSize(NSSize(width: 120, height: wideHeight))
        let narrowHeight = textView.intrinsicContentSize.height

        XCTAssertGreaterThan(narrowHeight, wideHeight * 2)
        XCTAssertEqual(
            narrowHeight,
            textView.measuredHeight(constrainedTo: 120),
            accuracy: 0.5
        )
    }

    func testMeasurementIncludesTrailingEmptyLine() {
        let textView = makeTextView(width: 240)
        textView.setText("First line")
        let lineHeight = textView.measuredHeight(constrainedTo: 240)

        textView.setText("First line\n")
        let heightWithTrailingLine = textView.measuredHeight(constrainedTo: 240)

        XCTAssertGreaterThan(heightWithTrailingLine, lineHeight)
    }

    func testFontChangeInvalidatesTextHeight() {
        let textView = makeTextView(width: 160)
        textView.setText("A value that wraps across several lines at this width")
        let compactHeight = textView.measuredHeight(constrainedTo: 160)

        textView.configure(fontSize: 20, usesMonospacedFont: true)
        let largeHeight = textView.measuredHeight(constrainedTo: 160)

        XCTAssertGreaterThan(largeHeight, compactHeight)
    }

    private func makeTextView(width: CGFloat) -> MeasuringSelectableTextView {
        let textView = MeasuringSelectableTextView(
            frame: NSRect(x: 0, y: 0, width: width, height: 1)
        )
        textView.configure(fontSize: 12, usesMonospacedFont: true)
        return textView
    }
}

@MainActor
private final class TextSizingTestModel: ObservableObject {
    @Published var text: String

    init(text: String) {
        self.text = text
    }
}

private struct TextSizingTestHarness: View {
    @ObservedObject var model: TextSizingTestModel

    var body: some View {
        SelectableMonospacedTextView(
            text: model.text,
            fontSize: 12,
            usesMonospacedFont: true
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}
