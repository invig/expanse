// Every end-to-end case, by area (docs/regression). Each area's file lists its manual cases.
@MainActor let allCases: [Case] =
    NAV.cases + EDIT.cases + PLACE.cases + TRACK.cases + SIZE.cases + PERSIST.cases + DISPLAY.cases + SPACES.cases
    + CAPTURE.cases + UI.cases + SETUP.cases + SUPPORT.cases + UPDATE.cases + URLCases.cases + SEC.cases
