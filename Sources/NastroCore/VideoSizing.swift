import Foundation

public enum VideoSizing {
    /// Scales down so the long side fits `maxLongSide` (never up), keeps the aspect ratio,
    /// and rounds both dimensions down to an even number.
    public static func outputSize(sourceWidth: Int, sourceHeight: Int,
                                  maxLongSide: Int) -> (width: Int, height: Int) {
        let longSide = max(sourceWidth, sourceHeight)
        var w = sourceWidth, h = sourceHeight
        if longSide > maxLongSide, longSide > 0 {
            w = sourceWidth * maxLongSide / longSide
            h = sourceHeight * maxLongSide / longSide
        }
        return (w - w % 2, h - h % 2)
    }
}
