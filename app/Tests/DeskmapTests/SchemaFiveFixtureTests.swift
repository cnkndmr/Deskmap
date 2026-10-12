import Foundation
import Testing
@testable import Deskmap

/// A schema-5 `rules.json` in the exact shape the main-branch build writes
/// (per-profile `desktopNames`, `desktopNameSpaces`, `ghostDesktops`,
/// `plannedDesktops`; no top-level copies; `pendingRemovals` shared with
/// `profileID`). This build must read it without loss and write it back the
/// same way (12.10: the live file was already written by that build).
struct SchemaFiveFixtureTests {

    static let fixture = """
    {
      "activeProfileID" : "P-ACTIVE",
      "enabled" : true,
      "pendingRemovals" : {
        "undocked|builtin" : [
          {
            "desktop" : 5,
            "profileID" : "P-ACTIVE",
            "space" : 55
          }
        ]
      },
      "profiles" : [
        {
          "desktopNameSpaces" : {
            "docked|external" : {
              "2" : 20
            }
          },
          "desktopNames" : {
            "docked|external" : {
              "2" : "Nova"
            }
          },
          "id" : "P-ACTIVE",
          "name" : "Office",
          "plannedDesktops" : {
            "docked|external" : 4
          },
          "rules" : [
            {
              "appName" : "Mail",
              "bundleID" : "com.apple.mail",
              "docked" : {
                "desktop" : 2,
                "layout" : {
                  "h" : 1,
                  "w" : 1,
                  "x" : 0,
                  "y" : 0
                },
                "screen" : "external"
              },
              "id" : "R1",
              "tokens" : [

              ]
            }
          ]
        },
        {
          "desktopNames" : {
            "undocked|builtin" : {
              "3" : "Notes"
            }
          },
          "ghostDesktops" : [
            {
              "deletedAt" : 800000000,
              "desktop" : 4,
              "id" : "G1",
              "name" : "Old",
              "pins" : [
                {
                  "destination" : {
                    "desktop" : 4,
                    "layout" : {
                      "h" : 1,
                      "w" : 1,
                      "x" : 0,
                      "y" : 0
                    },
                    "screen" : "builtin"
                  },
                  "mode" : "undocked",
                  "profileID" : "P-OTHER",
                  "rule" : {
                    "appName" : "Notes",
                    "bundleID" : "com.apple.Notes",
                    "id" : "R2",
                    "tokens" : [

                    ]
                  }
                }
              ],
              "screen" : "builtin"
            }
          ],
          "id" : "P-OTHER",
          "name" : "Café",
          "rules" : [
            {
              "appName" : "Notes",
              "bundleID" : "com.apple.Notes",
              "id" : "R3",
              "tokens" : [

              ],
              "undocked" : {
                "desktop" : 3,
                "layout" : {
                  "h" : 1,
                  "w" : 1,
                  "x" : 0,
                  "y" : 0
                },
                "screen" : "builtin"
              }
            }
          ]
        }
      ],
      "rules" : [
        {
          "appName" : "Mail",
          "bundleID" : "com.apple.mail",
          "docked" : {
            "desktop" : 2,
            "layout" : {
              "h" : 1,
              "w" : 1,
              "x" : 0,
              "y" : 0
            },
            "screen" : "external"
          },
          "id" : "R1",
          "tokens" : [

          ]
        }
      ],
      "screens" : [

      ],
      "setupNoticeDismissed" : false,
      "version" : 5
    }
    """

    private func decoded() throws -> Document {
        try JSONDecoder().decode(Document.self, from: Data(Self.fixture.utf8))
    }

    @Test func readsEveryProfileStateWithoutLoss() throws {
        let d = try decoded()
        #expect(!d.isFromNewerVersion)
        #expect(d.droppedRuleCount == 0)
        #expect(d.activeProfileID == "P-ACTIVE")
        // Working copy = active profile's state.
        #expect(d.rules.map(\.id) == ["R1"])
        #expect(d.desktopNames == ["docked|external": ["2": "Nova"]])
        #expect(d.desktopNameSpaces == ["docked|external": ["2": 20]])
        #expect(d.plannedDesktops == ["docked|external": 4])
        #expect(d.ghostDesktops.isEmpty)
        #expect(d.pendingRemovals["undocked|builtin"]
                == [PendingRemoval(desktop: 5, space: 55, profileID: "P-ACTIVE")])
        let other = try #require(d.profiles.first { $0.id == "P-OTHER" })
        #expect(other.desktopNames == ["undocked|builtin": ["3": "Notes"]])
        #expect(other.desktopNameSpaces.isEmpty)
        #expect(other.ghostDesktops.map(\.id) == ["G1"])
        #expect(other.ghostDesktops.first?.pins.map(\.rule.id) == ["R2"])
        #expect(other.plannedDesktops.isEmpty)
        #expect(other.rules.map(\.id) == ["R3"])
    }

    @Test func writesTheSameFileBack() throws {
        let written = try Store.encode(decoded())
        #expect(String(decoding: written, as: UTF8.self) == Self.fixture)
    }

    @Test func switchingLoadsTheOtherProfileAndBackKeepsBoth() throws {
        var d = try decoded()
        d.switchProfile(to: "P-OTHER")
        #expect(d.desktopNames == ["undocked|builtin": ["3": "Notes"]])
        #expect(d.ghostDesktops.map(\.id) == ["G1"])
        d.switchProfile(to: "P-ACTIVE")
        #expect(String(decoding: try Store.encode(d), as: UTF8.self) == Self.fixture)
    }
}
