import AppKit

/// How the timeline follows workspace motions and live window resizes.
/// During a workspace motion the canvas re-wraps its visible rows on every
/// frame, at the width the columns' path gives it; during a live resize the
/// motion presenter shows the rows (`NativeTimelineMotionPresenter`). Either
/// way the canvas lays everything out once the width settles.
extension NativeMessageTimelineCoordinator {
        func workspaceMotionObservations(_ center: NotificationCenter) -> [NSObjectProtocol] {
            [
                center.addObserver(forName: WorkspaceLayoutMotion.didBegin, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.canvas?.dismissHoverPresentationForScroll()
                    }
                },
                // A column that covers the conversation rather than resizing
                // it changes no frame here; the timeline follows its path.
                center.addObserver(forName: WorkspaceConversationWidthPath.didAdvance, object: nil, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let scrollView = self.scrollView, self.motionWidth(of: scrollView) != nil
                            || abs(scrollView.contentView.bounds.width - self.lastViewportSize.width) >= 0.5
                        else { return }
                        _ = self.reconcileViewportGeometryIfNeeded()
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
                        self.motionPresenter.begin()
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
            guard motionPresenter.isActive, !WorkspaceLayoutMotion.isMoving,
                  scrollView?.window?.inLiveResize != true
            else { return }
            guard pendingLayoutWidth != nil else {
                // The height may have changed alone: the canvas catches up
                // with the viewport it skipped.
                motionPresenter.end()
                _ = reconcileViewportGeometryIfNeeded()
                return
            }
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

        /// While the workspace's columns move, the width they give the
        /// timeline, if it differs from its own: a column that slides over
        /// the conversation leaves its frame alone.
        func motionWidth(of scrollView: NSScrollView) -> CGFloat? {
            let path = WorkspaceConversationWidthPath.shared
            guard path.isMoving, let width = path.width(of: scrollView),
                  abs(width - scrollView.contentView.bounds.width) >= 0.5
            else { return nil }
            return width
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
            guard motionPresenter.isActive, !reflowsWidth,
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
}
