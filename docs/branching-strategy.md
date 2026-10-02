# Branching strategy — cicd-workshop

## Model
Trunk-based development with short-lived feature branches.

## Branches
- `main` — always deployable. Protected: no direct pushes, review required,
  pipeline must pass.
- `feature/<short-description>` — one unit of work. Lifetime: hours to 2 days.
- `hotfix/<short-description>` — urgent production fix, same rules, faster review.

## Why not GitFlow
We deploy continuously and never support more than one released version at a
time. A `release/*` branch would only add a merge step and a place for changes
to go stale. If we ever have to patch an old version in the field, revisit this.

## Serverless-specific rules
1. A branch that changes an EventBridge event schema is a HIGH RISK branch
   regardless of how few lines it touches. It requires an expand/contract plan
   in the PR description before review.
2. Branches that add resources to `template.yaml` should be merged promptly —
   two such branches WILL conflict in YAML that reviewers read less carefully
   than code.
3. Incomplete work ships behind a feature flag, not on a long-lived branch.
4. The deployment unit is the function. A branch touching one handler has a
   small blast radius; a branch touching the shared event bus does not.

## Commits
Conventional Commits. The version number and CHANGELOG are generated from the
log, so the format is load-bearing, not cosmetic.

## Releases
Annotated tags on `main`, semantic versioning. MAJOR is reserved for breaking
EVENT SCHEMA changes, not for internal refactors.
