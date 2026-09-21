import CoreGraphics

/// 팝오버 옆에 보조 창(시스템 색상 패널 등)을 놓을 자리를 고르는 순수 계산.
///
/// 좌표계는 AppKit 화면 좌표(원점 왼쪽 아래, y가 위로 증가)를 쓴다. 보조 모니터는
/// 화면 원점이 음수일 수 있으므로 `screen`을 그대로 받아서 그 사각형 안으로만 민다.
public enum PanelPlacement {
    /// 팝오버 왼쪽에 `gap`만큼 띄워 붙인다. 왼쪽에 폭이 모자라면 오른쪽에 붙이고,
    /// 양쪽 다 모자라면 화면 안으로 밀어 넣는다. 세로는 팝오버 위쪽에 맞춘다
    /// (팝오버는 메뉴바 바로 아래에서 아래로 자라므로, 위를 맞추면 둘이 나란히 보인다).
    ///
    /// - Returns: 패널 프레임의 원점(왼쪽 아래).
    public static func besidePopover(
        panelSize: CGSize,
        popover: CGRect,
        screen: CGRect,
        gap: CGFloat = 12
    ) -> CGPoint {
        var x = popover.minX - gap - panelSize.width
        if x < screen.minX {
            x = popover.maxX + gap
        }
        let y = popover.maxY - panelSize.height
        return CGPoint(
            x: clamp(x, lower: screen.minX, upper: screen.maxX - panelSize.width),
            y: clamp(y, lower: screen.minY, upper: screen.maxY - panelSize.height))
    }

    /// `upper`가 `lower`보다 작을 수 있다(패널이 화면보다 클 때). 그때는 `lower`를 쓴다.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return lower }
        return min(max(value, lower), upper)
    }
}
