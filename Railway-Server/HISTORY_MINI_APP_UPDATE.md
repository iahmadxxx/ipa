# History Mini App Update

- `/سجل`, `/history`, and `/log` now open a Telegram Mini App.
- Old workout records can be edited or deleted by individual set.
- Deleting a set automatically renumbers the remaining sets in that exercise session.
- All changes are written to the existing `sets` table.
- The AI coach and performance analytics already read from this same table, so edited/deleted history is reflected automatically in future answers and reports.
- No new Railway variables, database, domain, or manual migration are required.
