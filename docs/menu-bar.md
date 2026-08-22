# Flowmo — menu-bar glance

The window remains the product. The status item shows the Core clock while the window is hidden.

## In

- One `NSStatusItem`. Title is the same clock the window would show (remaining on timed beats, count-up on Focus, frozen with a leading `·` while recovery-paused, `Flowmo` when idle).
- Click brings the existing window forward. Does not Continue a paused session.
- Same Core timestamps as the window. No second clock.
- Title ink follows `Atmosphere.of(status)`: mute when idle, faint when paused, phase ink otherwise.

## Out

Pause, Start, Skip, scores, extra menus, replacing the window.

WHEN Focus is showing in the window  
THE SYSTEM SHALL still not put a menu bar *inside* that frame.

WHEN the process is running  
THE SYSTEM SHALL show a status-item clock from Core status.
