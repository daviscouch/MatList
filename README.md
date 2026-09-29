# MatList

A profession shopping list for **World of Warcraft: Forever** (beta, interface 16001). Queue up recipes, and MatList tells you which crafting materials you still need, counting your bags plus a cached copy of your bank.

## Install

1. Download this repo (green **Code** button > **Download ZIP**) or `git clone` it.
2. Copy the inner **`MatList`** folder (the one containing `MatList.toc`) to:
   `World of Warcraft\_classic_beta_\Interface\AddOns\MatList\`
3. Restart the game (or `/reload` after first launch) and make sure MatList is enabled in the AddOns list.

## Use

- `/matlist` toggles the shopping list window (drag the title bar to move, drag the bottom-right corner to resize).
- Open a profession window, select a recipe, set a quantity and click **Add to MatList** (below the profession window). Adding a recipe that's already listed increases its quantity.
- Hover any item on your list to see `MatList: have / need (Recipe A, Recipe B)`.
- Open your bank once so MatList can cache what's in it; the window shows how old that cache is.

| Command | What it does |
|---|---|
| `/matlist add [recipeID or link] [qty]` | Add a recipe. With a recipe selected in the profession window, `/matlist add 5` makes 5. |
| `/matlist set <name or ID> <qty>` | Change a recipe's quantity (0 removes it). |
| `/matlist remove <name or ID>` | Remove a recipe. |
| `/matlist clear` | Remove everything. |
| `/matlist export` / `import` | Back up / restore the list as a line of text. |
| `/matlist debug` | Print diagnostics for bug reports. |

Quantity means number of crafts (not number of items produced). All quality tiers of a material are counted together.

## Important: SavedVariables on the Forever beta

Per community reports, the Forever beta client may not restore SavedVariables at login, so your list can disappear each session. **Use `/matlist export` to save your list somewhere and `/matlist import` to restore it.**

## Status

Version 0.1.0. Built against the retail (Midnight-era) API as documented publicly and against a community capture of Forever's API. The profession-window hook, tooltip hook and bank events could not be verified without the game, so the addon checks each at runtime and reports problems in chat rather than erroring. See `/matlist debug`.

## Roadmap (not built yet)

Vendor vs. farmed flags, nested crafting expansion, cross-character counts, goal alerts. The data model already reserves room for these.

## License

MIT
