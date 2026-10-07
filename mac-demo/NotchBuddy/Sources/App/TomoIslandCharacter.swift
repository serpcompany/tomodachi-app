import SwiftUI
import TomoCore

// MARK: - Tomo in the notch island (the shared drawing is TomoBlob, in TomoCore)

/// Tomo in the island: a Canvas redrawn every frame, gaze following the cursor.
struct TomoCharacterView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    @StateObject private var blob = TomoBlob()

    var body: some View {
        // The Canvas must read the timeline's date, or SwiftUI won't redraw it every frame.
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                blob.frameDate = timeline.date
                let g = gaze()
                blob.lookX = g.x
                blob.lookY = g.y
                blob.particleOverhang = particleOverhang
                blob.step()
                blob.draw(context, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, s in blob.setState(s) }
        .onAppear {
            blob.setState(state.effectiveState, force: true)
            blob.setGrowth(TomoGame.shared.growthStep)
        }
        .tomoReactions(blob)
    }

    /// Cursor direction relative to Tomo, −1…1 (positive y = above).
    private func gaze() -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (w, h) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress,
                                nw: state.notchWidth, nh: state.notchHeight)
        let (bx, by, _, _) = botPosition(mode: state.mode, view: state.view, islandW: w, islandH: h,
                                         uploadProgress: state.uploadProgress)
        let screenX = screen.frame.midX - w / 2 + bx
        return CGPoint(x: tanh((state.mousePosition.x - screenX) / 260),
                       y: -tanh((state.mousePosition.y - by) / 200))
    }
}

/// Small decorative Tomo for the leftover agent pills (switched off in Tomodachi; removed with issue #1).
struct MiniBotCanvasView: View {
    let task: AgentTask
    @StateObject private var blob: TomoBlob = {
        let c = TomoBlob()
        c.isMini = true
        c.setGrowth(1)
        return c
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                blob.frameDate = timeline.date
                blob.step()
                blob.draw(context, size: size)
            }
        }
        .onChange(of: task.state) { _, s in blob.setState(s) }
        .onAppear { blob.setState(task.state, force: true) }
    }
}
