#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ID=MD-OWNERSHIP-GEOSPATIAL-002
BR=fix/geospatial-routing-ownership-v2-20261007
OLD=aba0a9baeaf8604b0ef831e6525541196c442bd5
MAIN=49f6aadb065d96983bbb7dfaf377658b35d84b2c
STORE="$HOME/repos/touristic-digital-platform.git"
WT="$HOME/worktrees/MD-OWNERSHIP-GEOSPATIAL-002-acquire-v2-20261007-d74ed0ad769f"
cd "$HOME/morro-termux-control"
./scripts/tdp-worktreectl.sh refresh
test "$(git --git-dir="$STORE" rev-parse refs/heads/main)" = "$MAIN"
test -d "$WT"
cd "$WT"
test "$(git branch --show-current)" = "$BR"
test "$(git rev-parse HEAD)" = "$OLD"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
git fetch origin main --prune
FETCHED="$(git rev-parse FETCH_HEAD)"
test "$FETCHED" = "$MAIN"
git merge-base --is-ancestor "$OLD" "$MAIN"
git merge --ff-only "$MAIN"
test "$(git rev-parse HEAD)" = "$MAIN"
export GITHUB_REPOSITORY=luizanunciostoca/touristic-digital-platform
node tooling/mdctl/mdctl.mjs claim reanchor ".morro/changesets/$ID.json" --base-sha "$MAIN"
git diff --check
git add ".morro/changesets/$ID.json" .github/morro-control/claims.json .github/morro-control/events.ndjson
git commit -m "chore(control-plane): reanchor geospatial ownership v2"
python3 - <<'PY'
import json
from pathlib import Path
p=Path(".morro/ownership.json"); d=json.loads(p.read_text())
assert d["version"]==2 and not any(x.get("id")=="geospatial-routing" for x in d["domains"])
g={"id":"geospatial-routing","pathPrefixes":["packages/geospatial/","tooling/geospatial/","apps/morro-digital-platform/src/config/destination.test.ts","docs/adr/0003-geospatial-provider-strategy.md"],"contracts":[]}
i=next(i for i,x in enumerate(d["domains"]) if x.get("id")=="ci-release")
d["domains"].insert(i,g); p.write_text(json.dumps(d,indent=2)+"\n")
p=Path("tooling/ci/local-fast-gate.test.mjs"); s=p.read_text()
assert 'canonical ownership covers Wave 5 geospatial routing paths' not in s
m='test("ownership admission fails closed for uncovered paths", () => {'; assert m in s
t='''test("canonical ownership covers Wave 5 geospatial routing paths", () => {
  const ownership = JSON.parse(readFileSync(".morro/ownership.json", "utf8"));
  const domain = ownership.domains.find(
    (candidate) => candidate.id === "geospatial-routing",
  );
  assert.ok(domain);
  assert.deepEqual(domain.pathPrefixes, [
    "packages/geospatial/",
    "tooling/geospatial/",
    "apps/morro-digital-platform/src/config/destination.test.ts",
    "docs/adr/0003-geospatial-provider-strategy.md",
  ]);
  assert.deepEqual(
    assertOwnershipCoverage(
      [
        "apps/morro-digital-platform/src/config/destination.test.ts",
        "docs/adr/0003-geospatial-provider-strategy.md",
        "packages/geospatial/src/index.ts",
        "packages/geospatial/src/routing-policy.test.ts",
        "tooling/geospatial/routing-policy-promotion.contract.mjs",
      ],
      { domains: [domain] },
    ),
    { covered: 5 },
  );
});

'''
p.write_text(s.replace(m,t+m,1))
p=Path(".morro/changesets/MD-OWNERSHIP-GEOSPATIAL-002.json"); x=json.loads(p.read_text())
assert x["baseSha"]=="49f6aadb065d96983bbb7dfaf377658b35d84b2c" and x["state"]=="IMPLEMENTING"
x["state"]="LOCAL_PROVEN"; p.write_text(json.dumps(x,indent=2)+"\n")
PY
pnpm install --frozen-lockfile --prefer-offline
pnpm exec prettier --write .morro/ownership.json ".morro/changesets/$ID.json" tooling/ci/local-fast-gate.test.mjs
node --test tooling/ci/local-fast-gate.test.mjs tooling/tdp-max/validate-config.test.mjs
git diff --check
git add .morro/ownership.json ".morro/changesets/$ID.json" tooling/ci/local-fast-gate.test.mjs
git commit -m "fix(control-plane): cover geospatial routing ownership v2"
HEAD="$(git rev-parse HEAD)"; TREE="$(git rev-parse HEAD^{tree})"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git --git-dir="$STORE" rev-parse refs/heads/main)" = "$MAIN"
pnpm fastfix:prepare
pnpm fastfix:admission
pnpm fastfix:certify
test "$(git rev-parse HEAD)" = "$HEAD"
test "$(git rev-parse HEAD^{tree})" = "$TREE"
test -z "$(git status --porcelain=v1 --untracked-files=all)"
test "$(git --git-dir="$STORE" rev-parse refs/heads/main)" = "$MAIN"
git push origin "$BR"
test "$(git ls-remote --exit-code origin "refs/heads/$BR" | awk '{print $1}')" = "$HEAD"
printf 'STATUS=PASS\nMAIN=%s\nHEAD=%s\nTREE=%s\nWT=%s\n' "$MAIN" "$HEAD" "$TREE" "$WT"
