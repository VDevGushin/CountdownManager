import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Real, tiny media generated only by explicit isolated regression/smoke fixtures.
package enum UISmokeAttachmentMedia {
    package static func make(in directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = ["Фото к встрече.png", "Документ с двумя страницами.pdf", "Короткое видео.mp4",
                     "Повреждённый пример.png", "Переписка.txt"]
            + (6...15).map { "Материал \($0) — длинное имя с подробностями встречи и дополнительными пояснениями.txt" }
        let urls = names.map { directory.appendingPathComponent($0) }
        guard urls.allSatisfy({ !FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try writePNG(to: urls[0])
        try writePDF(to: urls[1])
        guard let video = Data(base64Encoded: movieBase64, options: .ignoreUnknownCharacters) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try video.write(to: urls[2])
        try Data("Intentionally invalid PNG fixture".utf8).write(to: urls[3])
        for (index, url) in urls.enumerated() where index >= 4 {
            try Data("Isolated synthetic correspondence \(index + 1)".utf8).write(to: url)
        }
        return urls
    }

    private static func writePNG(to url: URL) throws {
        guard let context = CGContext(data: nil, width: 128, height: 80, bitsPerComponent: 8, bytesPerRow: 512,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 80))
        context.setFillColor(CGColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 10, y: 12, width: 35, height: 56))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func writePDF(to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 160, height: 100)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        // Distinct page colors let acceptance prove page zero, not merely any PDF representation.
        for color in [CGColor(red: 0.95, green: 0.05, blue: 0.05, alpha: 1),
                      CGColor(red: 0.05, green: 0.95, blue: 0.05, alpha: 1)] {
            context.beginPDFPage(nil)
            context.setFillColor(color)
            context.fill(box)
            context.endPDFPage()
        }
        context.closePDF()
    }

    // 0.6-second 96×64 H.264 MP4, three identical blue/gold synthetic frames; no runtime encoder.
    private static let movieBase64 = """
        AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMtbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAAlgAAQAAAQAA
        AAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAA
        Alh0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAlgAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAA
        AAAAAAAAAAAAAABAAAAAAGAAAABAAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAJYAAAAAAABAAAAAAHQbWRpYQAAACBtZGhk
        AAAAAAAAAAAAAAAAAAAoAAAAGABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABe21p
        bmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAATtzdGJsAAAAt3N0c2QA
        AAAAAAAAAQAAAKdhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAGAAQABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMSBsaWJ4
        MjY0AAAAAAAAAAAAAAAAGP//AAAALWF2Y0MBQsAK/+EAFmdCwAraGJsBEAAAAwAQAAADAKDxImoBAARozg/IAAAAEHBhc3AAAAAB
        AAAAAQAAABRidHJ0AAAAAAAAJ0UAAAAAAAAAGHN0dHMAAAAAAAAAAQAAAAMAAAgAAAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAcc3Rz
        YwAAAAAAAAABAAAAAQAAAAMAAAABAAAAIHN0c3oAAAAAAAAAAAAAAAMAAALDAAAAJQAAAAoAAAAUc3RjbwAAAAAAAAABAAADXQAA
        AGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAAABxkYXRh
        AAAAAQAAAABMYXZmNjMuMS4xMDEAAAAIZnJlZQAAAvptZGF0AAACUwYF//9P3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2
        NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cu
        dmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTEgZGVibG9jaz0wOjA6MCBhbmFseXNlPTA6MCBt
        ZT1kaWEgc3VibWU9MCBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0wIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRy
        ZWxsaXM9MCA4eDhkY3Q9MCBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0wIHRocmVh
        ZHM9MiBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVy
        YXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTAgd2VpZ2h0cD0wIGtleWludD0yNTAga2V5aW50X21pbj01
        IHNjZW5lY3V0PTAgaW50cmFfcmVmcmVzaD0wIHJjPWNyZiBtYnRyZWU9MCBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBt
        YXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0wAIAAAABoZYiEOhGA4AAguAACCCAAIApPggABADAMFLBAAFgc8a82HwcA
        AQ3AABDBwQAAQJwABAMQgAAgHAA6JycnWbrp666666euuubAcAAQXQABBAAAEAQB3ggABACAOElAgAC4Mce1LieuuvAAAAAhQZog
        E68EkUMUMUMUMPBX1GFJT8x+bgkigxQYoMUGNBpoAAAABkGaQBOgzA==
        """
}
