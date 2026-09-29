# MatList: context for Claude sessions

Profession shopping-list addon for World of Warcraft: Forever (beta, interface 16001). Owner: Davis, a non-technical founder who has never coded. Drive execution yourself, and don't hand him commands to run.

## Status (v0.1.0, built 2026-09-29)
MVP is written and pushed but has NOT been tested in-game. Syntax-checked and logic-tested only (luaparse + fengari in a scratch npm folder; no Lua installed locally). Next step: Davis tests at home and reports back.

## Where things are
- Addon files: `MatList/` (Core, Data, Counting, UI, Tooltip, Professions, .toc). README.md at the root has install and usage.
- Install path in game: `World of Warcraft\_classic_beta_\Interface\AddOns\MatList\`

## Key facts
- The "hated-wow-mcp" server does not exist (an AI invented the name). API was verified against warcraft.wiki.gg and the community capture https://github.com/Thunderz96/forever-addon-kit (`data/forever_api.json`, build 69893).
- Forever runs the retail (Midnight 12.x) API, not Classic. Registering an unknown event throws, so all registrations are pcall'd.
- The Forever beta client writes SavedVariables but never restores them. Export/import (`/matlist export|import`) is the persistence path.
- `C_TradeSkillUI.GetSelectedRecipeID` does not exist in Forever. Selected recipe comes from `ProfessionsFrame.CraftingPage.SchematicForm`.
- Unverified in-game: profession frame structure, button placement (below ProfessionsFrame), `TooltipDataProcessor`, bank open/close events, whether `C_Item.GetItemCount(includeBank)` works with the bank closed.

## When Davis reports a bug
Ask for the Lua error text and the output of `/matlist debug`. Fix, syntax-check, push.

## Decisions made
Quantity = number of crafts. All quality tiers of a reagent count together. Adding an existing recipe increases its quantity. Only required ("Basic") reagents are counted.

## Phase 2 (not built)
Vendor vs farmed flags, nested crafting, cross-character counts (reserved as `db.mats` / `db.alts`), goal alerts.
