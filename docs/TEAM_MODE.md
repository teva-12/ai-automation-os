# Team mode (planned)

Goal: a 5-person group where the bot sends each member the jobs that fit *them*, one member submits the proposal,
and a won job is split into tasks for everyone so delivery is faster.

1. **Routing** - score each new job against every member's skills (rules first, LLM only for the final analysis) and notify the best one or two members privately.
2. **Claim** - `claim J12` locks the job to one member; if nobody answers within a time window it returns to the pool.
3. **Proposal** - draft from the claiming member's own CV; they review and submit from their own platform account.
4. **Win -> project** - create a project, split tasks by specialty, give each member schedule entries, post progress in the team group.

Already supported by the schema: multiple users, per-user skills/matches/applications/schedule/tasks.
To build: per-member watcher notifications, the claim command, project/task split, member onboarding.

Rules: every proposal comes from its author's real account (no shared or fake accounts); each member sees only their own data;
LLM usage must be budgeted (shared paid tier or per-member keys) because free tiers do not scale to five users.
