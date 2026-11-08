// 로고 원본(assets/logo-source.png)에서 앱 아이콘과 메뉴바 아이콘을 만든다.
//
//   swiftc -O tools/make_icons.swift -o /tmp/make_icons && /tmp/make_icons
//   (프로젝트 루트에서 실행)
//
// 결과물
//   assets/logo.png         README용 로고 (1024, 투명 배경)
//   assets/AppIcon.icns     앱 아이콘
//   assets/MenuBarIcon.png  메뉴바 템플릿 아이콘 (검은 부분만 남긴 실루엣)
import AppKit

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
let source = NSBitmapImageRep(data: try! Data(contentsOf: assets.appendingPathComponent("logo-source.png")))!
let srcCG = source.cgImage!

// 원본 안에서 둥근 사각형(아이콘 몸체)이 있는 영역 (픽셀 밝기를 재서 구한 값)
let body = CGRect(x: 113, y: 116, width: 1029, height: 1011) // 위쪽 기준 좌표

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func savePNG(_ image: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - 앱 아이콘 (macOS 아이콘 격자: 1024 캔버스 안에 824 몸체, 둥근 모서리, 그림자)

func appIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = bitmap(size, size)
    let inset = s * 100 / 1024
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10 / 1024), blur: s * 20 / 1024,
                  color: NSColor.black.withAlphaComponent(0.3).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 몸체 그림 (원본 잘라서 둥근 사각형 안에)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    let cropped = srcCG.cropping(to: body)!
    ctx.draw(cropped, in: rect)
    ctx.restoreGState()

    return ctx.makeImage()!
}

savePNG(appIcon(size: 1024), assets.appendingPathComponent("logo.png"))

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    savePNG(appIcon(size: pt), iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    savePNG(appIcon(size: pt * 2), iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()

// MARK: - 메뉴바 아이콘 (어두운 픽셀만 남긴 템플릿 이미지)

let w = source.pixelsWide, h = source.pixelsHigh
var alpha = [UInt8](repeating: 0, count: w * h)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in Int(body.minY + 20)..<Int(body.maxY - 20) {
    for x in Int(body.minX + 20)..<Int(body.maxX - 20) {
        let b = source.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.brightnessComponent
        // 밝기 0.25 이하 = 완전 불투명, 0.85 이상 = 투명, 사이는 부드럽게
        let a = max(0, min(1, (0.85 - b) / 0.6))
        guard a > 0.02 else { continue }
        alpha[y * w + x] = UInt8(a * 255)
        if a > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
let pad = 4
minX -= pad; minY -= pad; maxX += pad; maxY += pad
let cw = maxX - minX + 1, ch = maxY - minY + 1

let mask = bitmap(cw, ch)
let data = mask.data!.bindMemory(to: UInt8.self, capacity: mask.bytesPerRow * ch)
for y in 0..<ch {
    for x in 0..<cw {
        let a = alpha[(y + minY) * w + (x + minX)]
        let i = y * mask.bytesPerRow + x * 4
        data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = a // 검정 + 알파 (premultiplied)
    }
}
let full = mask.makeImage()!

// 메뉴바 높이 18pt 기준 @2x (높이 36px)
let outH = 36
let outW = Int((Double(cw) / Double(ch) * Double(outH)).rounded())
let out = bitmap(outW, outH)
out.interpolationQuality = .high
out.draw(full, in: CGRect(x: 0, y: 0, width: outW, height: outH))
savePNG(out.makeImage()!, assets.appendingPathComponent("MenuBarIcon.png"))

print("완료: logo.png, AppIcon.icns, MenuBarIcon.png (\(outW)x\(outH))")
