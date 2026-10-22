import AppKit

/// How the timeline follows workspace motions and live window resizes:
/// the motion presenter shows the rows while the width changes
/// (`NativeTimelineMotionPresenter`), and the canvas lays out once the width
/// settles.
extension NativeMessageTimelineCoordinator {
        func workspaceMotionObservations(_ center: NotificationCenter) -> [NSObjectProtocol] {
            [
                center.addObserver(forName: WorkspaceLayoutMotion.didBegin, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.canvas?.dismissHoverPresentationForScroll()
                        self?.motionPresenter.begin(.workspaceMotion)
                    }
                },
                center.addObserver(forName: WorkspaceLayoutMotion.didSettle, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.motionPresenterDidFinishMotion()
                        guard self.scrollIdleTask == nil else { return }
                        self.canvas?.allowHoverPresentationAfterScroll()
                    }
                },
                center.addObserver(forName: NSWindow.willStartLiveResizeNotification, object: nil, queue: .main) { [weak self] notification in
                    let window = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        guard let self, window != nil, window === self.scrollView?.window else { return }
                        self.motionPresenter.begin(.liveResize)
                    }
                },
                center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: nil, queue: .main) { [weak self] notification in
                    let window = notification.object as? NSWindow
                    MainActor.assumeIsolated {
                        guard let self, window != nil, window === self.scrollView?.window else { return }
                        self.motionPresenterDidFinishMotion()
                    }
                },
            ]
        }

        /// Once the width stops changing, the canvas lays out for it and
        /// takes the rows back from the motion presenter.
        func motionPresenterDidFinishMotion() {
            guard motionPresenter.isEngaged, !WorkspaceLayoutMotion.isMoving,
                  scrollView?.window?.inLiveResize != true
            else { return }
            // Armed for a motion that left this timeline's width alone.
            guard motionPresenter.isActive else {
                motionPresenter.end()
                return
            }
            guard pendingLayoutWidth != nil else {
                // The height may have changed alone: the canvas catches up
                // with the viewport it skipped.
                motionPresenter.end()
                _ = reconcileViewportGeometryIfNeeded()
                return
            }
            // A live resize ends without a motion to wait for.
            widthRelayoutTask?.cancel()
            widthRelayoutTask = nil
            applyPendingWidthRelayout()
        }

        /// Before the canvas lays out for the settled width: puts the
        /// presenter's bitmaps for it in the canvas's cache.
        /// - Returns: Whether this update hands the rows back to the canvas.
        func prepareMotionPresenterForSettle(width: CGFloat, reflowsWidth: Bool, restoresPreview: Bool) -> Bool {
            guard motionPresenter.isActive, reflowsWidth || restoresPreview else { return false }
            if reflowsWidth { motionPresenter.seedCanvas(width: width) }
            return true
        }

        /// Kept apart from `reconcileViewportGeometryIfNeeded`, which is at
        /// its complexity limit.
        func endMotionPresentation(_ ends: Bool) {
            if ends { motionPresenter.end() }
        }

        /// While the motion presenter shows the rows, moves them to this
        /// frame's width; the canvas lays out once, for the final width.
        /// - Returns: Whether the presenter handled the frame.
        func presentMotionFrame(
            width: CGFloat, viewportSize: CGSize, widthChanged: Bool, sizeChanged: Bool, reflowsWidth: Bool
        ) -> Bool {
            guard motionPresenter.isEngaged, !reflowsWidth,
                  widthChanged || sizeChanged || motionPresenter.presentedWidth.map({ abs($0 - width) >= 0.5 }) == true,
                  motionPresenter.present(width: width)
            else { return false }
            // `lastViewportSize` stays the canvas's, which lays out for the
            // viewport once the presenter hands back.
            if widthChanged {
                scheduleRelayoutForWidthChange(width)
            } else {
                widthRelayoutTask?.cancel()
                widthRelayoutTask = nil
                pendingLayoutWidth = nil
            }
            return true
        }

        /// While a workspace motion resizes the timeline on every frame, its
        /// rows reflow every few frames rather than on each one; between
        /// reflows the canvas keeps its rows and the clip view follows the
        /// motion. Reflowing every frame cost most of a frame's budget.
        /// Returns whether this width change waits for the next reflow.
        func deferMotionPreview() -> Bool {
            guard WorkspaceLayoutMotion.isMoving else {
                lastMotionPreview = nil
                return false
            }
            let interval = Duration.milliseconds(50)
            let now = ContinuousClock.now
            // The first reflow waits an interval too, so the columns are
            // already moving when its cost lands.
            if lastMotionPreview == nil { lastMotionPreview = now }
            guard let last = lastMotionPreview, now - last < interval else {
                lastMotionPreview = now
                return false
            }
            if throttledPreviewTask == nil {
                throttledPreviewTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(until: last + interval)
                    guard let self, !Task.isCancelled else { return }
                    throttledPreviewTask = nil
                    _ = reconcileViewportGeometryIfNeeded()
                }
            }
            return true
        }
}
