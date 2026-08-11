#!/usr/bin/env swift
// RunningCrew DMG 배경 이미지 생성기 — scripts/dmg-assets/ 에 1x·2x PNG 를 쓴다.
// 좌표계는 bottom-left 원점. create-dmg 아이콘 배치(top 기준 y=190)와 맞춰
// 화살표를 y=230(=420-190) 높이에 그린다.
import AppKit

let W: CGFloat = 660
let H: CGFloat = 420
let outDir = "scripts/dmg-assets"

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for (scale, name) in [(CGFloat(1), "dmg-background.png"), (CGFloat(2), "dmg-background@2x.png")] {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H) // 포인트 크기 → 2x 는 144dpi 메타데이터

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // 배경: 아주 옅은 세로 그라데이션
    NSGradient(
        starting: NSColor(calibratedWhite: 0.93, alpha: 1),
        ending: NSColor(calibratedWhite: 0.975, alpha: 1)
    )!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // 상단 타이틀 + 브랜드 마크 (트랙 링 + 러너 점)
    let title = "RunningCrew" as NSString
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .bold),
        .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
    ]
    let titleSize = title.size(withAttributes: titleAttrs)
    let markRadius: CGFloat = 13
    let markGap: CGFloat = 12
    let totalWidth = markRadius * 2 + markGap + titleSize.width
    let startX = (W - totalWidth) / 2
    let centerY = H - 58

    let blue = NSColor(calibratedRed: 0.192, green: 0.510, blue: 0.965, alpha: 1)
    let markCenter = NSPoint(x: startX + markRadius, y: centerY)
    let ring = NSBezierPath()
    // 52° → 318° 를 반시계로 돌아 우측(러너 점 자리)에만 갭을 남긴다
    ring.appendArc(withCenter: markCenter, radius: markRadius, startAngle: 52, endAngle: -42, clockwise: false)
    ring.lineWidth = 5.5
    ring.lineCapStyle = .round
    blue.setStroke()
    ring.stroke()
    let dotR: CGFloat = 5.5
    let runnerAngle = 8.0 * .pi / 180
    let dotCenter = NSPoint(
        x: markCenter.x + markRadius * cos(runnerAngle),
        y: markCenter.y + markRadius * sin(runnerAngle)
    )
    blue.setFill()
    NSBezierPath(ovalIn: NSRect(x: dotCenter.x - dotR, y: dotCenter.y - dotR, width: dotR * 2, height: dotR * 2)).fill()

    title.draw(
        at: NSPoint(x: startX + markRadius * 2 + markGap, y: centerY - titleSize.height / 2),
        withAttributes: titleAttrs
    )

    // 화살표 (앱 → Applications)
    let arrowY: CGFloat = 230
    let gray = NSColor(calibratedWhite: 0.72, alpha: 1)
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 280, y: arrowY))
    shaft.line(to: NSPoint(x: 368, y: arrowY))
    shaft.lineWidth = 4
    shaft.lineCapStyle = .round
    gray.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 362, y: arrowY + 9))
    head.line(to: NSPoint(x: 380, y: arrowY))
    head.line(to: NSPoint(x: 362, y: arrowY - 9))
    head.close()
    gray.setFill()
    head.fill()

    // 하단 안내문
    let hint = "RunningCrew 를 Applications 폴더로 끌어다 놓으세요" as NSString
    let hintAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.55, alpha: 1),
    ]
    let hintSize = hint.size(withAttributes: hintAttrs)
    hint.draw(at: NSPoint(x: (W - hintSize.width) / 2, y: 34), withAttributes: hintAttrs)

    NSGraphicsContext.restoreGraphicsState()

    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("saved: \(outDir)/\(name) (\(Int(W * scale))x\(Int(H * scale)))")
}
