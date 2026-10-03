#!/usr/bin/env bash
# sn-lab.sh goto <N> - make ~/cicd-workshop and this lab account look like the start of Lab N of
# "CI/CD for Serverless and Event-Driven Systems", from whatever state they are in now.
#
# Use it to join a lab after missing earlier ones, or to redo a lab from a clean start.
# Your own work is kept: before anything changes, your current commit is tagged mine-before-lab<N>.
#
# Supported so far: goto 2 to 8. goto 5 to 8 only forwards; they need the earlier labs' stacks to exist. Later labs are added as each lab's checkpoint is proven.
set -euo pipefail

REPO=~/cicd-workshop
ORIGIN="$HOME/remotes/cicd-workshop.git"
# Where the checkpoints come from. Override with SN_CHECKPOINTS_URL.
CHECKPOINTS_URL="${SN_CHECKPOINTS_URL:-https://github.com/syntax-nebula/cicd-workshop.git}"
CHECKPOINTS_PROFILE="${SN_CHECKPOINTS_PROFILE:-default}"
SUPPORTED="2 3 4 5 6 7 8"

say()  { printf '\n--- %s\n' "$*"; }
die()  { printf '\nsn-lab: %s\n' "$*" >&2; exit 1; }
gone() { "$@" >/dev/null 2>&1 || true; }   # remove if present; fine if already gone

# Git with the checkpoint credentials for this one command only; nothing is written to ~/.gitconfig.
cgit() {
  case "$CHECKPOINTS_URL" in
    https://git-codecommit.*)
      git -c credential.helper= \
          -c "credential.helper=!aws codecommit credential-helper --profile $CHECKPOINTS_PROFILE \$@" \
          -c credential.UseHttpPath=true "$@" ;;
    *) git "$@" ;;
  esac
}

# Only touch AWS as the lab's own identities, so a stray run elsewhere can never delete anything.
in_lab_account() {
  local arn
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null) || return 1
  case "$arn" in
    *:user/LabUser|*:assumed-role/SyntaxNebulaLabSessionManagerRole/*) return 0 ;;
    *) echo "not a lab identity ($arn): AWS left untouched"; return 1 ;;
  esac
}

usage() { echo "usage: sn-lab.sh goto <N>   (supported: $SUPPORTED)"; exit 2; }

# ---------------------------------------------------------------------------------------------
# Step 1 - clean up what Lab N and later labs created. Nothing to do for labs never reached.
# ---------------------------------------------------------------------------------------------
cleanup_from() {
  local n=$1
  if [ "$n" -le 5 ] && in_lab_account; then
    for st in cicd-workshop-pipeline cicd-workshop-staging cicd-workshop-prod; do
      aws cloudformation describe-stacks --stack-name "$st" >/dev/null 2>&1 \
        && die "Lab 5's stack $st exists. Going back to Lab $n from Lab 5 or later is not supported by this jumper yet. Nothing was changed."
    done
  fi
  if [ "$n" -le 3 ]; then
    say "Removing what Lab 3 and later created"
    if in_lab_account; then
      for id in cicd-workshop/payment-api cicd-workshop/npm; do
        gone aws secretsmanager delete-secret --secret-id "$id" --force-delete-without-recovery
        # Lab 3 creates the same names again; wait until Secrets Manager has really let them go
        for _ in $(seq 30); do aws secretsmanager describe-secret --secret-id "$id" >/dev/null 2>&1 || break; sleep 2; done
      done
      gone aws ssm delete-parameter --name /cicd-workshop/artifact-bucket
    fi
    gone git -C "$REPO" config --unset core.hooksPath
  fi
  if [ "$n" -le 2 ]; then
    say "Removing what Lab 2 and later created"
    if in_lab_account && aws cloudformation describe-stacks --stack-name cicd-workshop-dev >/dev/null 2>&1; then
      echo "deleting stack cicd-workshop-dev (Lab 2 creates it again)"
      aws cloudformation delete-stack --stack-name cicd-workshop-dev
      aws cloudformation wait stack-delete-complete --stack-name cicd-workshop-dev || true
    fi
    rm -f "$REPO/samconfig.toml"
  fi
}

# ---------------------------------------------------------------------------------------------
# Step 2 - the project at checkpoint lab<N-1>-done, here and in origin.
# ---------------------------------------------------------------------------------------------
project_to() {
  local n=$1 tag="${SN_CHECKPOINT_TAG:-lab$(( $1 - 1 ))-done}"
  say "Project: $REPO at $tag"
  command -v git >/dev/null || { echo "installing Git (Lab 1)"; sudo dnf install -y -q git; }

  if [ -z "$(git config --global user.name || true)" ]; then
    read -r -p "Your name for Git commits: " name
    read -r -p "Your email for Git commits: " email
    git config --global user.name "$name"
    git config --global user.email "$email"
  fi
  git config --global init.defaultBranch main
  git config --global core.editor nano

  if [ -d "$REPO/.git" ]; then
    if git -C "$REPO" rev-parse -q --verify HEAD >/dev/null; then
      local keep="mine-before-lab$n" i=2
      while git -C "$REPO" rev-parse -q --verify "refs/tags/$keep" >/dev/null; do keep="mine-before-lab$n-$i"; i=$((i + 1)); done
      git -C "$REPO" tag "$keep" HEAD                      # never moves an earlier copy
      echo "your work is kept as tag $keep"
    fi
  else
    [ -e "$REPO" ] && die "$REPO exists but is not a Git repository. Move it away and run again."
    git init -q "$REPO"
  fi

  cd "$REPO"
  gone git remote remove checkpoints
  git remote add checkpoints "$CHECKPOINTS_URL"
  cgit fetch -q --tags --force checkpoints 2>&1 | { grep -v '^remote:' || true; }   # hide the server's progress lines
  git remote remove checkpoints          # the tags stay; a student who did the labs has only origin
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "checkpoint $tag not found in $CHECKPOINTS_URL"

  git switch -q -C main "$tag"
  git reset -q --hard "$tag"
  # Keep only tags inside the checkpoint's history; later checkpoints and releases would show up in
  # git log --all. The student's own saved copies stay.
  for t in $(git tag -l); do
    case "$t" in mine-before-*) continue ;; esac
    git merge-base --is-ancestor "$t" HEAD 2>/dev/null || git tag -d "$t" >/dev/null
  done
  git clean -q -fdx                      # untracked and ignored files go too (node_modules, .aws-sam, coverage,
                                         # samconfig.toml), so Lab N starts as on a fresh host; goto 3+ runs npm ci
  git branch --format='%(refname:short)' | { grep -vx main || true; } | xargs -r git branch -q -D

  # origin: the local bare repository Lab 1 created
  if [ ! -d "$ORIGIN" ]; then git init -q --bare "$ORIGIN"; fi
  if git remote get-url origin >/dev/null 2>&1; then git remote set-url origin "$ORIGIN"
  else git remote add origin "$ORIGIN"; fi
  git push -q --force origin main
  git tag -l | grep -v -e '^mine-before-' -e '^scout-' | sed 's#^#refs/tags/#' | xargs -r git push -q --force origin   # your saved copies stay local
  # origin keeps no tag the jump removed here, or the next git pull would bring it back
  for t in $(git ls-remote --tags origin | sed -n 's#.*refs/tags/\([^^]*\)$#\1#p' | sort -u); do
    git rev-parse -q --verify "refs/tags/$t" >/dev/null || git push -q origin ":refs/tags/$t"
  done
  git branch -q --set-upstream-to=origin/main main
}

# ---------------------------------------------------------------------------------------------
# Step 3 - create what every lab before N created, outside the project. Each step may run twice.
# ---------------------------------------------------------------------------------------------
create_before() {
  local n=$1
  # Lab 1 creates nothing in AWS.
  if [ "$n" -ge 3 ]; then lab2_left_behind "$n"; fi
  if [ "$n" -ge 4 ]; then lab3_left_behind; fi
  if [ "$n" -ge 6 ]; then lab5_left_behind; fi
  if [ "$n" -ge 7 ]; then lab6_left_behind; fi
  if [ "$n" -ge 8 ]; then lab7_left_behind; fi
  if [ "$n" -ge 3 ] && [ "$n" -le 4 ]; then drop_lambda_versions; fi
}

# Lab 4 publishes Lambda versions; Lab 4 starts from "only $LATEST". After the redeploy has removed
# the alias, delete the numbered versions so a redo of Lab 4 starts as the page says.
drop_lambda_versions() {
  local v
  for v in $(aws lambda list-versions-by-function --function-name cicd-workshop-order-api                --query 'Versions[?Version!=`$LATEST`].Version' --output text 2>/dev/null); do
    aws lambda delete-function --function-name cicd-workshop-order-api --qualifier "$v" >/dev/null 2>&1 || true
  done
}

# Lab 5: the three stage stacks and the pipeline. Building them from nothing is not supported yet;
# a forward jump finds them where Lab 5 left them.
lab5_left_behind() {
  say "Lab 5: the stage stacks and the pipeline"
  local st
  for st in cicd-workshop-dev cicd-workshop-staging cicd-workshop-prod cicd-workshop-pipeline; do
    aws cloudformation describe-stacks --stack-name "$st" >/dev/null 2>&1 \
      || die "stack $st does not exist. Jumping to Lab 6 needs Lab 5's stacks, and creating them is not supported by this jumper yet."
  done
  echo "the stage stacks and the pipeline are in place"
}

# Lab 6: the verify stages in the pipeline (its scripts are in the project).
lab6_left_behind() {
  say "Lab 6: the verify stages"
  aws codepipeline get-pipeline --name cicd-workshop-pipeline \
    --query 'pipeline.stages[].actions[].name' --output text | grep -qw VerifyDev \
    || die "the pipeline has no VerifyDev stage. Jumping to Lab 7 needs Lab 6's pipeline changes, and adding them is not supported by this jumper yet."
  echo "the verify stages are in place"
}

# Lab 7: the manual approval before prod, in the pipeline stack.
lab7_left_behind() {
  say "Lab 7: the approval before prod"
  aws codepipeline get-pipeline --name cicd-workshop-pipeline \
    --query 'pipeline.stages[].name' --output text | grep -qw ApproveProd \
    || die "the pipeline has no ApproveProd stage. Jumping to Lab 8 needs Lab 7's pipeline changes, and adding them is not supported by this jumper yet."
  echo "the approval stage is in place"
}

# Lab 3: the scanners, the payment secret at its last value, the build's parameter and npm token,
# and the pre-commit hook. The stack itself was deployed from the checkpoint by lab2_left_behind.
lab3_left_behind() {
  say "Lab 3: scanners, secrets, parameter and the pre-commit hook"
  command -v pip3 >/dev/null || sudo dnf install -y -q python3-pip
  [ -x "$HOME/.local/bin/checkov" ] || pip3 install --user --quiet cfn-lint checkov   # ~/.local/bin is on PATH only in interactive shells
  local payment='{"apiKey":"sk_test_FAKE_ROTATED_AGAIN_x9y8z7","endpoint":"https://payments-v2.example.invalid"}'
  if aws secretsmanager describe-secret --secret-id cicd-workshop/payment-api >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id cicd-workshop/payment-api --secret-string "$payment" >/dev/null
  else
    aws secretsmanager create-secret --name cicd-workshop/payment-api \
      --description "Fake payment provider credentials for the CI/CD workshop" --secret-string "$payment" >/dev/null
  fi
  aws ssm put-parameter --name /cicd-workshop/artifact-bucket \
    --value "cicd-workshop-artifacts-$(aws sts get-caller-identity --query Account --output text)" \
    --type String --overwrite >/dev/null
  aws secretsmanager describe-secret --secret-id cicd-workshop/npm >/dev/null 2>&1 \
    || aws secretsmanager create-secret --name cicd-workshop/npm \
         --secret-string '{"token":"npm_FAKE_TOKEN_FOR_WORKSHOP_ONLY"}' >/dev/null
  git -C "$REPO" config core.hooksPath .githooks
  echo "secrets, parameter and hook in place"
}

# Lab 2: Node.js and the SAM CLI, the LabUser keys, the project's packages, and the dev stack
# deployed by the guided deploy, which also writes the samconfig.toml later labs rely on.
lab2_left_behind() {
  say "Lab 2: tools, packages and the dev stack"
  command -v node >/dev/null || sudo dnf install -y -q nodejs22 nodejs22-npm
  if ! command -v sam >/dev/null; then
    curl -sL "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-arm64.zip" -o /tmp/sam.zip
    unzip -q -o /tmp/sam.zip -d /tmp/sam-installation
    sudo /tmp/sam-installation/install --update >/dev/null
  fi
  local arn
  arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)
  case "$arn" in
    *:user/LabUser) ;;
    *) die "AWS is not set up with your LabUser access key yet (now: ${arn:-no credentials}).
Do Lab 2, Task 4, 'Configure credentials': create an access key and run aws configure. Then run this again." ;;
  esac
  [ "$(aws configure get region || true)" = eu-central-1 ] || aws configure set region eu-central-1

  cd "$REPO"
  npm ci --silent
  # From Lab 6 on, the pipeline deploys the stacks and samconfig.toml is part of the project:
  # a guided deploy here would rewrite a tracked file. lab5_left_behind checks the stacks instead.
  [ "${1:-3}" -ge 6 ] && return 0
  sam build >/tmp/sn-lab-build.log 2>&1 || { tail -20 /tmp/sn-lab-build.log; die "sam build failed"; }
  # The guided deploy, answered as Lab 2's table says: Enter five times, y for the API with no
  # authentication, Enter three times. It writes samconfig.toml exactly as Lab 2 does.
  printf '\n\n\n\n\ny\n\n\n\n' | sam deploy --guided --stack-name cicd-workshop-dev \
    --capabilities CAPABILITY_IAM --resolve-s3 --region eu-central-1 --no-fail-on-empty-changeset \n    >/tmp/sn-lab-deploy.log 2>&1 || { tail -20 /tmp/sn-lab-deploy.log; die "sam deploy failed"; }
  aws cloudformation describe-stacks --stack-name cicd-workshop-dev --query 'Stacks[0].StackStatus' --output text
}

# ---------------------------------------------------------------------------------------------
# Step 4 - what to paste into each terminal.
# ---------------------------------------------------------------------------------------------
exports_for() {
  local n=$1
  if [ "$n" -le 2 ] || [ "$n" -ge 6 ]; then
    echo "Nothing to export: Lab $n sets up its own variables."
    case "$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" in
      *:user/LabUser) if [ "$n" -le 2 ]; then echo "Your AWS CLI already uses LabUser: in Lab 2 Task 4, skip creating a new access key."; fi ;;
    esac
    return
  fi
  echo "Paste these into every terminal you use for Lab $n:"
  local out var
  for pair in ApiUrl:API_URL ShippingQueueUrl:QUEUE_URL; do
    out=${pair%%:*}; var=${pair##*:}
    echo "export $var=$(aws cloudformation describe-stacks --stack-name cicd-workshop-dev \
      --query "Stacks[0].Outputs[?OutputKey=='$out'].OutputValue" --output text)"
  done
}

[ "${1:-}" = goto ] || usage
N="${2:-}"
case " $SUPPORTED " in *" $N "*) ;; *) usage ;; esac

echo "sn-lab: going to the start of Lab $N."
echo "Everything Lab $N and later labs created is removed, and $REPO is set to the end of Lab $((N - 1))."
read -r -p "Type 'go' to continue: " ok
[ "$ok" = go ] || { echo "Nothing changed."; exit 1; }

# Nothing changes until the checkpoint is known to exist.
TAG="${SN_CHECKPOINT_TAG:-lab$((N - 1))-done}"   # SN_CHECKPOINT_TAG: start from another checkpoint tag
cgit ls-remote --tags "$CHECKPOINTS_URL" "refs/tags/$TAG" 2>/dev/null | grep -q .   || die "checkpoint $TAG is not available yet at $CHECKPOINTS_URL. Nothing was changed."

cleanup_from "$N"
project_to "$N"
create_before "$N"
say "Done"
exports_for "$N"
echo "Start Lab $N at Task 0."
