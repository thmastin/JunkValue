# JunkValue

![JunkValue](media/logo.png)

JunkValue is a standalone LibDataBroker source that displays the vendor value of sellable gray items in bags 0-4. It shows a compact money total, and its tooltip shows the total and number of stacks. It never sells, picks up, or deletes items.

## Install

Copy the `JunkValue` folder into your Forever client's `Interface\AddOns` directory, so `JunkValue.toc` is at `Interface\AddOns\JunkValue\JunkValue.toc`. Restart or reload the client and enable JunkValue in the AddOns list.

## EllesmereUI DataBars

Open EllesmereUI's DataBars settings, choose the bar you want to configure, and set its block type to **Broker Plugin**. Select **Junk** (the source is named `JunkValue`) from the broker plugin list.

## Options

Open the JunkValue settings panel with `/junkvalue`, right-click the broker bar, or find **JunkValue** under Game Menu > Options > AddOns. The panel controls icon visibility and choice, merchant summary, gold-only display, and the EllesmereUI junk marker. It also shows both custom item lists, lets you add an item ID or shift-click an item link, and has per-item Remove buttons. Clear lists requires a second click within five seconds.

Slash commands remain available: `/junkvalue add <itemlink or id>` counts an item as junk, including non-gray items; `/junkvalue never <itemlink or id>` keeps an item out, even if gray; `/junkvalue remove <itemlink or id>` removes it from both lists; `/junkvalue list` prints both lists; `/junkvalue clear` asks for `/junkvalue clear confirm` within 10 seconds. Alt+right-click bag items to toggle gray items on the keep list and non-gray items on the always-junk list. The lists are account-wide SavedVariables. Custom items without a vendor price are skipped. JunkValue never sells, picks up, or deletes items.

## Tests

Run `luajit tests/run.lua` from this folder.

## Versioning

JunkValue uses Semantic Versioning (`MAJOR.MINOR.PATCH`):

- **PATCH (1.1.x):** bug fixes and polish, with no new behavior. Small fixes are grouped into one patch release.
- **MINOR (1.x.0):** new features that don't break existing setups.
- **MAJOR (x.0.0):** breaking changes, such as renaming the data broker, resetting saved settings, or dropping a supported client.

A release is tagged only after an in-game check. GitHub Actions builds and uploads releases to CurseForge on `v*` tags.
