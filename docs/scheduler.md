# Node Scheduler Guide

Schedule automated node start/stop operations.

## Overview

The scheduler uses the Linux `at` command to schedule node operations at specific times. Useful for:
- Coordinated upgrades
- Maintenance windows
- Automated restarts

## Usage

1. Launch Valley of 0G:
   ```bash
   bash <(curl -s https://raw.githubusercontent.com/hubofvalley/Mainnet-Guides/main/0g%20\(zero-gravity\)/resources/valleyof0G.sh)
   ```
2. Select **"Node Scheduler"** from the menu

## Menu Options

1. **List scheduled jobs** - View all pending scheduled operations
2. **Stop and disable 0g services** - Schedule a future stop
3. **Restart and enable 0g services** - Schedule a future restart
4. **Remove a scheduled job** - Cancel a pending operation
5. **Exit**

## Scheduling Format

When scheduling, provide UTC time:
- Year (4 digits, e.g., 2026)
- Month (1-12)
- Day (1-31)
- Hour (0-23, 24h format)
- Minute (0-59)
- Second (0-59)

The script converts UTC to your server's local time for execution.

## Job Management

### View Scheduled Jobs
Shows job ID, action type, and scheduled time.

### Remove a Job
Enter the job ID to cancel a scheduled operation.

## Log Location

Job logs are stored at:
```
$HOME/.0gchaind/0g-home/0g_schedule_jobs.log
```

## Notes

- Jobs run as root (uses `sudo at`)
- Seconds are handled via sleep command (at only supports minute precision)
- All times are interpreted as UTC

## Related Documentation

- [Validator Node Guide](validator-node.md)
