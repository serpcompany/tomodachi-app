# Screens

The screens both apps show, and the seam that keeps them the same on the Mac and the iPhone. What a
learner sees is in [growth.md](growth.md) ("Seeing Tomo grow") and [concepts.md](concepts.md)
("Settings"); the other systems are mapped in [architecture.md](architecture.md).

## The seam

Tomo, Words, Together, Settings and About are SwiftUI views in TomoCore (`TomoGrowthScreen`,
`TomoWordsScreen`, `TomoTogetherScreen`, `TomoSettingsScreen`, `TomoAboutScreen`), shown by both
shells: the Mac in the Tomodachi window with a sidebar (`TomoAppWindow`), the iPhone as tabs around
the play screen (`TomoPhoneHome`, which wraps `TomoPhoneView` unchanged). `TomoScreens.swift` holds
the seam: `TomoScreen` (the screens), `TomoScreenNav` (which one shows; `confirmingStartOver`, so
the Mac's menu asks the same way Settings does) and `TomoFeatures` (what this version offers: the AI
page and the "I'm learning" picker show only with the testing tools). What only one device has goes
into Settings' `device` slot: open at login on the Mac (`TomoLoginItem`, off until the learner turns
it on), reminders on the iPhone ([#88](https://github.com/serpcompany/tomodachi-app/issues/88)). The
Mac's main menu and its menu bar icon's menu share one list of commands (`TomoMenus`). Invariants:
the screens read `TomoGame`, `TomoProgress` and `TomoStats` and decide nothing themselves; Start
over always asks first; colours read in light and dark mode (a system colour, or a light and a dark
value), each word stage's pill reads at 5:1 and looks different from the stage before it in both
(`TomoStagePill.selfTest`, [#236](https://github.com/serpcompany/tomodachi-app/issues/236)), a dark
picture gets a light disc on a dark card (`TomoPictureView`), and sliders are
`TomoSlider` ([#195](https://github.com/serpcompany/tomodachi-app/issues/195)); the testing tools
(`TomoTestingTools`, after ⌥-clicking the menu bar icon) never touch the saved Tomo. New screens
take the Tomo they show (its progress, look and material), so a friend can have its own: Together
does ([stats.md](stats.md)), and takes the clipboard from the shell (`copy`), since TomoCore has no
pasteboard.
