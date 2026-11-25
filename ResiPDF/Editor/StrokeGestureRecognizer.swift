import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Reconoce un trazo de un solo dedo/Pencil desde el primer contacto
/// (sin el umbral de movimiento de UIPanGestureRecognizer) y conserva
/// los puntos "coalesced" para trazos suaves a 240 Hz.
final class StrokeGestureRecognizer: UIGestureRecognizer {
    private(set) var tracked: UITouch?
    private var pending: [CGPoint] = []

    /// Devuelve los puntos nuevos desde la última llamada (coordenadas de `view`).
    func takeSamples() -> [CGPoint] {
        defer { pending.removeAll() }
        if pending.isEmpty, let t = tracked, let v = view { return [t.location(in: v)] }
        return pending
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, touches.count == 1, let touch = touches.first else {
            // Un segundo dedo => no es un trazo (deja que el scroll/zoom actúe).
            state = (state == .possible) ? .failed : .cancelled
            return
        }
        tracked = touch
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t), let v = view else { return }
        let samples = event.coalescedTouches(for: t) ?? [t]
        pending.append(contentsOf: samples.map { $0.location(in: v) })
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t), let v = view else { return }
        pending.append(t.location(in: v))
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        super.reset()
        tracked = nil
        pending.removeAll()
    }
}
