# Daily GitHub sync

The local Windows task `FinPilot Approved GitHub Sync` runs at 23:00 in the computer's Eastern time zone. It targets `rafa-legend21/finpilot-assistant` through the existing `origin` Git remote.

## Approval rule

Only an exact feature-branch commit that the user has explicitly confirmed is eligible. After reviewing the full branch changes and creating a Conventional Commit, record that approval with:

```powershell
.\scripts\approve_for_daily_sync.ps1 -Branch feat/example -Commit <full-commit-sha>
```

The task pushes that SHA to the matching remote branch. Newer unapproved local commits and uncommitted files are excluded. It never force-pushes or merges into `main`. A failed push stays pending for the next run; details are in `.finpilot-sync/sync.log`.

The task uses local Git authentication and runs only while the user is signed in and the computer can reach GitHub. Use Windows Task Scheduler to inspect, run, or disable it. No commits are approved by installing the task.

To register this task on another Windows computer with the repository checked out, run `scripts/register_daily_sync.ps1` in PowerShell while Windows uses the Eastern time zone.
