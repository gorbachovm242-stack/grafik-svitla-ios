// Малює всі зразки віджета (PreviewSamples) у PNG. На GitHub Actions теку задає змінна PREVIEW_DIR
// (TEST_RUNNER_PREVIEW_DIR у xcodebuild), і картинки стають артефактом запуску: їх видно без Mac і iPhone.
import XCTest
import SwiftUI
import UIKit
@testable import GrafikSvitla

final class WidgetPreviewTests: XCTestCase {
    @MainActor
    func testRenderAllWidgetSamples() throws {
        let env = ProcessInfo.processInfo.environment["PREVIEW_DIR"]
        let dir = env.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("previews")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let samples = PreviewSamples.all()
        XCTAssertGreaterThan(samples.count, 20)
        for sample in samples {
            let renderer = ImageRenderer(content: sample.view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage, "не намалювався \(sample.name)")
            XCTAssertEqual(image.size.width, sample.size.width, accuracy: 1, sample.name)
            let png = try XCTUnwrap(image.pngData(), sample.name)
            try png.write(to: dir.appendingPathComponent("\(sample.name).png"))
            if env == nil {
                let attachment = XCTAttachment(image: image)
                attachment.name = sample.name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
