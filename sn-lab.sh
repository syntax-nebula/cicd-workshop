#!/usr/bin/env bash
# sn-lab.sh goto <N> - make ~/cicd-workshop and this lab account look like the start of Lab N of
# "CI/CD for Serverless and Event-Driven Systems", from whatever state they are in now.
#
# Use it to join a lab after missing earlier ones, or to redo a lab from a clean start.
# Your own work is kept: before anything changes, your current commit is tagged mine-before-lab<N>.
#
# Supported: goto 2 to 8, forwards and backwards. Going back to Lab 5 or earlier removes the pipeline
# and the staging and prod stacks. goto 6 to 8 deploy the pipeline as the previous lab left it and
# run it once.
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
  if in_lab_account; then finish_failed_deletes; fi
  if [ "$n" -le 8 ] && in_lab_account; then
    if aws cloudformation describe-stacks --stack-name cicd-workshop-tf-pipeline >/dev/null 2>&1 \
       || aws s3api head-bucket --bucket "cicd-workshop-tfstate-$(aws sts get-caller-identity --query Account --output text)" >/dev/null 2>&1; then
      die "Lab 8's Terraform resources exist. Run Lab 8's 'Clean up' section first, then run this again. Nothing was changed."
    fi
  fi
  if [ "$n" -le 6 ] && in_lab_account \
     && aws cloudformation describe-stacks --stack-name cicd-workshop-stuck >/dev/null 2>&1; then
    say "Removing Lab 6's practice stack"
    gone aws cloudformation delete-stack --stack-name cicd-workshop-stuck
    aws cloudformation wait stack-delete-complete --stack-name cicd-workshop-stuck \
      || die "the stack cicd-workshop-stuck did not delete. Finish Lab 6 Task 6 ('Recover a stuck stack'), then run this again."
  fi
  if [ "$n" -le 5 ] && in_lab_account; then lab5_teardown; fi
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

# Delete a stack if it exists, and wait. A stack the pipeline deployed is deleted with the pipeline's
# deploy role, so the pipeline stack always goes last.
delete_stack() {
  aws cloudformation describe-stacks --stack-name "$1" >/dev/null 2>&1 || return 0
  echo "deleting stack $1"
  aws cloudformation delete-stack --stack-name "$1"
  aws cloudformation wait stack-delete-complete --stack-name "$1" \
    || die "the stack $1 did not delete. Look at its events in the CloudFormation console, then run this again."
}

# Every object version and delete marker: a versioned bucket must be empty before it can be deleted.
empty_bucket() {
  python3 - "$1" <<'PY'
import json, subprocess, sys
bucket = sys.argv[1]
while True:
    raw = subprocess.check_output(["aws", "s3api", "list-object-versions", "--bucket", bucket,
                                   "--max-items", "1000", "--output", "json"]).strip()
    page = json.loads(raw) if raw else {}
    objs = [{"Key": o["Key"], "VersionId": o["VersionId"]}
            for o in (page.get("Versions") or []) + (page.get("DeleteMarkers") or [])]
    if not objs:
        break
    subprocess.check_call(["aws", "s3api", "delete-objects", "--bucket", bucket, "--delete",
                           json.dumps({"Objects": objs, "Quiet": True})], stdout=subprocess.DEVNULL)
PY
}

# Lab 5 and later: the staging and prod stacks, and the pipeline with its artifact bucket. The dev
# stack goes too if the pipeline ever deployed it: it is tied to the pipeline's deploy role, which is
# deleted with the pipeline. The jump deploys dev again from the checkpoint.
lab5_teardown() {
  local st role bucket found=""
  for st in cicd-workshop-pipeline cicd-workshop-staging cicd-workshop-prod; do
    if aws cloudformation describe-stacks --stack-name "$st" >/dev/null 2>&1; then found=1; fi
  done
  [ -n "$found" ] || return 0
  say "Removing Lab 5's stacks and the pipeline (5 to 10 minutes)"
  delete_stack cicd-workshop-prod
  delete_stack cicd-workshop-staging
  role=$(aws cloudformation describe-stacks --stack-name cicd-workshop-dev \
    --query 'Stacks[0].RoleARN' --output text 2>/dev/null || true)
  if [ -n "$role" ] && [ "$role" != None ]; then delete_stack cicd-workshop-dev; fi
  if aws cloudformation describe-stacks --stack-name cicd-workshop-pipeline >/dev/null 2>&1; then
    bucket=$(aws cloudformation describe-stacks --stack-name cicd-workshop-pipeline \
      --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucket`].OutputValue' --output text)
    if [ -n "$bucket" ] && [ "$bucket" != None ] && aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
      echo "emptying the artifact bucket $bucket"
      empty_bucket "$bucket"
    fi
    delete_stack cicd-workshop-pipeline
  fi
}

# A stack that an earlier clean-up left in DELETE_FAILED can be neither updated nor deployed over
# (Lab 7's old clean-up did this: it could not empty the versioned artifact bucket). Delete it again:
# the application stacks before the pipeline, whose artifact bucket is emptied of every version first.
finish_failed_deletes() {
  local st status bucket
  for st in cicd-workshop-prod cicd-workshop-staging cicd-workshop-dev cicd-workshop-pipeline; do
    status=$(aws cloudformation describe-stacks --stack-name "$st" \
      --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)
    [ "$status" = DELETE_FAILED ] || continue
    say "Finishing the delete of $st, which an earlier clean-up left half done"
    if [ "$st" = cicd-workshop-pipeline ]; then
      bucket="cicd-workshop-artifacts-$(aws sts get-caller-identity --query Account --output text)"
      if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
        echo "emptying the artifact bucket $bucket"
        empty_bucket "$bucket"
      fi
    fi
    delete_stack "$st"
  done
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
    if git -C "$REPO" rev-parse -q --verify HEAD >/dev/null        && ! { git -C "$REPO" tag --points-at HEAD | grep -q '^lab[0-9]*-done$'               && [ -z "$(git -C "$REPO" status --porcelain)" ]; }; then   # nothing of yours to keep on a bare checkpoint
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
  if [ "$n" -ge 6 ]; then pipeline_left_behind "$n"; fi
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

# Labs 5 to 7: the pipeline and the three stage stacks it deploys. The checkpoint holds the pipeline
# as the previous lab left it (Lab 6 adds the verify stages, Lab 7 the approval gate). Deploy it,
# publish the checkpoint, and let one run create or update dev, staging and prod, as Lab 5 Task 3
# does. A Lab 7 pipeline stops at ApproveProd: the jumper approves that run itself.
pipeline_left_behind() {
  local n=$1 bucket since
  local labs="Lab 5"
  if [ "$n" -gt 6 ]; then labs="Labs 5 to $((n - 1))"; fi
  say "$labs: the pipeline, and one run of it (5 to 20 minutes)"
  cd "$REPO"
  aws cloudformation deploy --template-file pipeline/pipeline.yaml --stack-name cicd-workshop-pipeline \
    --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset >/tmp/sn-lab-pipeline.log 2>&1 \
    || { tail -20 /tmp/sn-lab-pipeline.log; die "the pipeline stack did not deploy"; }
  bucket=$(aws cloudformation describe-stacks --stack-name cicd-workshop-pipeline \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucket`].OutputValue' --output text)
  aws ssm put-parameter --name /cicd-workshop/artifact-bucket --value "$bucket" \
    --type String --overwrite >/dev/null
  since=$(date -u +%s)
  ./scripts-publish.sh
  version=$(aws s3api head-object --bucket "$bucket" --key source/source.zip --query VersionId --output text)
  python3 - "$since" "$n" "$version" <<'PY' || die "the pipeline run did not succeed. Run: aws codepipeline get-pipeline-state --name cicd-workshop-pipeline"
import datetime, json, subprocess, sys, time
P = "cicd-workshop-pipeline"
def aws(*args):
    return json.loads(subprocess.check_output(["aws", *args, "--output", "json"]))
since = datetime.datetime.fromtimestamp(int(sys.argv[1]) - 10, datetime.timezone.utc)
start = time.time()
run = None
print("waiting for the pipeline run to start ...", flush=True)
while run is None:
    if time.time() - start > 600:
        sys.exit("no pipeline run started within 10 minutes of the publish")
    time.sleep(15)
    runs = aws("codepipeline", "list-pipeline-executions", "--pipeline-name", P,
               "--max-items", "10")["pipelineExecutionSummaries"]
    # the run of this publish: its source revision is the S3 version just uploaded
    mine = [r for r in runs if any(v.get("revisionId") == sys.argv[3] for v in r.get("sourceRevisions", []))]
    if not mine:   # no revision listed yet: the first run that started after the publish
        mine = [r for r in runs if not r.get("sourceRevisions")
                and datetime.datetime.fromisoformat(r["startTime"]) >= since]
    run = mine[-1]["pipelineExecutionId"] if mine else None
print("run", run, "started", flush=True)
shown = set()
while True:
    if time.time() - start > 3600:
        sys.exit("the pipeline run took more than an hour")
    time.sleep(20)
    status = aws("codepipeline", "get-pipeline-execution", "--pipeline-name", P,
                 "--pipeline-execution-id", run)["pipelineExecution"]["status"]
    for st in aws("codepipeline", "get-pipeline-state", "--name", P)["stageStates"]:
        le = st.get("latestExecution", {})
        if le.get("pipelineExecutionId") != run:
            continue
        if (st["stageName"], le["status"]) not in shown:
            shown.add((st["stageName"], le["status"]))
            print("  ", st["stageName"], le["status"], flush=True)
        for act in st.get("actionStates", []):
            ae = act.get("latestExecution", {})
            if ae.get("status") == "InProgress" and ae.get("token"):
                result = json.dumps({"summary": "Approved by sn-lab.sh goto " + sys.argv[2] +
                                                " to set up the lab", "status": "Approved"})
                subprocess.check_call(["aws", "codepipeline", "put-approval-result", "--pipeline-name", P,
                                       "--stage-name", st["stageName"], "--action-name", act["actionName"],
                                       "--token", ae["token"], "--result", result],
                                      stdout=subprocess.DEVNULL)
                print("   approved", act["actionName"], flush=True)
    if status == "Succeeded":
        print("the pipeline run succeeded: dev, staging and prod are deployed", flush=True)
        break
    if status not in ("InProgress",):
        sys.exit("the pipeline run ended " + status)
PY
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
  # a guided deploy here would rewrite a tracked file. pipeline_left_behind deploys them instead.
  [ "${1:-3}" -ge 6 ] && return 0
  sam build >/tmp/sn-lab-build.log 2>&1 || { tail -20 /tmp/sn-lab-build.log; die "sam build failed"; }
  # The guided deploy, answered as Lab 2's table says: Enter five times, y for the API with no
  # authentication, Enter three times. It writes samconfig.toml exactly as Lab 2 does.
  printf '\n\n\n\n\ny\n\n\n\n' | sam deploy --guided --stack-name cicd-workshop-dev \
    --capabilities CAPABILITY_IAM --resolve-s3 --region eu-central-1 --no-fail-on-empty-changeset \
    >/tmp/sn-lab-deploy.log 2>&1 || { tail -20 /tmp/sn-lab-deploy.log; die "sam deploy failed"; }
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
# Git first: a student who skipped Lab 1 has none, and the checkpoint check below needs it.
command -v git >/dev/null || { echo "installing Git (Lab 1)"; sudo dnf install -y -q git; }
# From Lab 3 on the jumper deploys with the LabUser key; stop now, before anything is changed.
if [ "$N" -ge 3 ]; then
  case "$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || true)" in
    *:user/LabUser) ;;
    *) die "AWS is not set up with your LabUser access key yet.
Do Lab 2, Task 4, 'Configure credentials': create an access key and run aws configure. Then run this again. Nothing was changed." ;;
  esac
fi
cgit ls-remote --tags "$CHECKPOINTS_URL" "refs/tags/$TAG" 2>/dev/null | grep -q .   || die "checkpoint $TAG is not available yet at $CHECKPOINTS_URL. Nothing was changed."

cleanup_from "$N"
project_to "$N"
create_before "$N"
say "Done"
exports_for "$N"
echo "Start Lab $N at Task 0."
