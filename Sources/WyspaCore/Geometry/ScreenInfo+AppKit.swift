import AppKit

extension ScreenInfo {
    @MainActor
    public static func current() -> [ScreenInfo] {
        let main = NSScreen.screens.first
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
            let notch = NotchMetrics.resolve(
                screenWidth: screen.frame.width,
                safeAreaTop: screen.safeAreaInsets.top,
                leftAuxWidth: screen.auxiliaryTopLeftArea?.width,
                rightAuxWidth: screen.auxiliaryTopRightArea?.width,
                menuBarHeight: menuBarHeight
            )
            return ScreenInfo(
                id: number.uint32Value,
                name: screen.localizedName,
                frame: screen.frame,
                notch: notch,
                isMain: screen == main
            )
        }
    }
}
