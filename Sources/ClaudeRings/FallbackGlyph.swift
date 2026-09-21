import SwiftUI

/// 로고 에셋이 없는 서비스를 위한 중립 대체 도형(방사형 별 모양). 특정 브랜드를
/// 나타내지 않는, 이 프로젝트에서 직접 그린 도형이다. 레이 개수·두께·안쪽 반지름을
/// 매개변수로 둬 다른 곳에서도 조정해 쓸 수 있게 한다.
struct FallbackGlyph: Shape {
    var rayCount: Int = 8
    var thicknessFraction: CGFloat = 0.55
    var innerRadiusFraction: CGFloat = 0.22

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusFraction
        let tipRadius = outerRadius * 0.12
        let anglePerRay = (2 * CGFloat.pi) / CGFloat(rayCount)
        let halfWidthAngle = anglePerRay * thicknessFraction / 2

        var path = Path()
        for i in 0..<rayCount {
            let angle = anglePerRay * CGFloat(i) - .pi / 2
            let leftBaseAngle = angle - halfWidthAngle
            let rightBaseAngle = angle + halfWidthAngle
            let leftBase = CGPoint(
                x: center.x + innerRadius * cos(leftBaseAngle),
                y: center.y + innerRadius * sin(leftBaseAngle))
            let rightBase = CGPoint(
                x: center.x + innerRadius * cos(rightBaseAngle),
                y: center.y + innerRadius * sin(rightBaseAngle))
            let tipCenter = CGPoint(
                x: center.x + (outerRadius - tipRadius) * cos(angle),
                y: center.y + (outerRadius - tipRadius) * sin(angle))

            path.move(to: leftBase)
            path.addLine(to: CGPoint(
                x: tipCenter.x + tipRadius * cos(leftBaseAngle),
                y: tipCenter.y + tipRadius * sin(leftBaseAngle)))
            path.addArc(
                center: tipCenter, radius: tipRadius,
                startAngle: .radians(Double(leftBaseAngle)), endAngle: .radians(Double(rightBaseAngle)),
                clockwise: false)
            path.addLine(to: rightBase)
            path.closeSubpath()
        }
        return path
    }
}
