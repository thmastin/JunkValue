# JunkValue

Standalone LibDataBroker data source for the vendor value of sellable gray items in bags 0–4. It does not sell, pick up, or delete items.

The optional `JunkValueDB.countEUIJunk` setting defaults to `false`. When enabled, items marked by `EUI_CategoryManager:IsJunk` are included, with the same value and price checks.

## Unit tests

From this folder, run:

```powershell
luajit tests/run.lua
```

The tests exercise the same summation helper loaded by the addon.
