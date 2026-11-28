# Changelog

## 1.4.4 - 28-Nov-2026 — Nearby zones and roster fixes

- Nearby recognizes more dungeon entrance areas, including Moonbrook for Deadmines and Dun Morogh for Hall of Thanes.
- Search and listing wait for the complete dungeon selection. Existing results and typed listing comments survive temporary data gaps.
- Group cards keep known class colors when individual roles are unavailable. Class exclusions use aggregate counts only when they agree with the visible roster.

## 1.4.3 - 27-Nov-2026 — City of Dalaran proximity

- When searching for City of Dalaran, players in Dalaran and Hillsbrad Foothills now appear as nearby. Players in Dalaran itself get the highest priority.

## 1.4.2 - 26-Nov-2026 — Search and listing fixes

- The first search can retry once after combat if it returned no players or groups and the search is still open.
- The dungeon picker refreshes when eligibility changes, so older entries can no longer change your selection.
- If WoW rejects a listing, you can retry from the same form with your comment intact.
- The built-in Group Finder opens correctly from the queue status icon and Friends list while the addon tab is visible.
- Release archives reject duplicate version entries in the changelog.

## 1.4.1 - 24-Nov-2026 — Full-width Group Finder tabs

- Players, Groups and Settings now share the full width of the tab row with equal spacing on both sides.

## 1.4.0 - 24-Nov-2026 — Group cards and search filters

- Group cards show tank, healer and damage slots in a consistent order. Gray icons mark confirmed openings. The listing's playstyle appears when WoW provides it.
- **Fits me** starts enabled and remembers your choice per character. Groups follow WoW's result order. Nearby players still appear first in their class columns.
- Dungeon and language menus share a compact design. Dungeon level ranges are aligned, selected languages appear on the button, and the Group Finder portrait stays visible.
- Keep saved dungeon choices while WoW loads the catalog. Keep card text, comments and extra dungeon counts readable with larger client fonts.
- Keep invite and suggest actions tied to the option you selected. Send the configured invite whisper when the listing role is temporarily unavailable, and recover cleanly after an uncertain listing attempt.
- Make completed ZIP files available without exposing a partial archive or overwriting an existing build.

## 1.3.0 - 24-Nov-2026 — Suggest Invite

- Use the plus button or **Suggest Invite** on a player card to suggest that player to your party leader.
- Keep dungeon search results while the details of an active listing are loading. Card actions resume when the selection can be verified.
- Build the ZIP from the same TOC and changelog bytes that were validated.

## 1.2.5 - 23-Nov-2026 — Unlist and dungeon search fixes

- Prevent duplicate unlist requests while WoW is processing a removal from the built-in Group Finder.
- Keep search results when dungeon availability is temporarily unreadable. Actions resume once the selection can be verified.
- Check that release ZIPs retain the full changelog.

## 1.2.4 - 22-Nov-2026 — Join roles and search recovery

- Join requests sent with a blank whisper template now include your selected roles. Clear all role selections to request an invite without specifying a role.
- Search results return automatically when WoW lifts its chat restriction. Reported listings stay hidden.
- The ZIP builder rejects release versions with leading zeros.

## 1.2.3 - 20-Nov-2026 — Packaging maintenance

- Fixed an issue where an interrupted ZIP write could block the next build. In-game behavior remains the same as in 1.2.2.

## 1.2.2 - 19-Nov-2026 — Listing and search recovery

- Keep Blizzard's Post button disabled while a listing request is pending. Restore its normal availability when the request settles and combat restrictions permit it.
- Retry automatic search on the next open after a search error or timeout.

## 1.2.1 - 18-Nov-2026 — Listing and filter fixes

- Wait for a listing submitted through Blizzard's window before allowing List Me to post again.
- Recover the first automatic search when Blizzard's search interrupts it.
- Keep Reset filters available when a search status message appears above retained results.
- Show all levels leaves dungeon selection empty when no dungeon is recommended. You can still select one manually.

## 1.2.0 - 17-Nov-2026 — Reset search filters

- Reset class and role filters when they hide all results, without changing the selected dungeons or search languages.

## 1.1.1 - 16-Nov-2026 — Listing and search fixes

- Wait for WoW to finish posting a listing with a comment before allowing another listing. If WoW immediately refuses the post, the comment editor stays open for a retry.
- Restore the comment controls after combat and show the full saved draft when you hover over it in Settings.
- Keep the dungeon menu closed after switching tabs or closing the window.
- Remove listings that WoW hides after a successful report and handle a search that WoW refuses immediately.

## 1.1.0 - 15-Nov-2026 — Listing comments in Settings

- Write a listing comment in WoW's own field inside Settings and publish from there. Your draft is saved for reference between sessions.
- Use List Me or List Party for a quick listing without a comment. List Party checks whether your party has room for the selected dungeons.
- Preserve existing Blizzard drafts and let you reopen the comment editor after WoW refreshes the form or a listing ends.
- Recover the first automatic search when the dungeon list is still loading, and keep equally ranked groups in WoW's result order.

## 1.0.2 - 15-Nov-2026 — Group roles and search fixes

- See which roles Room for me uses while in a party or listed solo.
- Show why only the party leader can list or unlist, and refresh the button when leadership changes.
- Give dungeon names their own row on group cards.
- Restore your previous roles when WoW immediately refuses to create a listing.
- Reduce stale results after overlapping searches, and resume queued searches after combat.

## 1.0.1 - 15-Nov-2026 — LFG Party Finder

- Party Finder Forever is now LFG Party Finder. Your settings and /pff command carry over.

## 1.0.0 - 15-Nov-2026 — First public release

- Open Party Finder Forever from the standard Group Finder binding or its map tab.
- Search multiple dungeons and browse players by class, with nearby players first.
- Review group composition and filter by filled roles or room for one of your roles.
- Share class exclusions and language preferences across the Players and Groups tabs.
- List yourself or your party with saved roles, playstyle, voice preferences and a New Player Friendly flag.
- Customize invite and join whispers and save a listing comment between sessions.
- Turning off automatic dungeon selection keeps only manually selected dungeons.
