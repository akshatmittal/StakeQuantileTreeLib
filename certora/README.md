# StakeQuantileTreeLib formal verification

The verification harness wraps the internal library and tracks authoritative support. The CVL specification proves:

- packed-key injectivity, exact path-lane updates, and off-path noninterference;
- exact total changes, zero-update identity, overflow rollback, split identity, and update commutativity;
- first-crossing child selection, lower-median equivalence, and quantile monotonicity;
- exact lower-median rank arithmetic; and
- weight/price containment, endpoint round trips, representatives, monotonicity, malformed-code rejection, and terminal clamping.

The harness limits aggregate support to `uint128`, matching the library's documented caller invariant and the production `MAX_STAKE` bound. Empty-tree median behavior is covered by the exhaustive Solidity test suite; the prover focuses on arbitrary storage states and state transitions.

## Run locally

The proof runs entirely locally and does not use `CERTORAKEY`. It requires Java 21, Rust, Z3, CVC5, and the Solidity compiler. Install the matching CLI and release JAR, then build the release's `tac_optimizer` helper:

```sh
sudo apt-get install z3 cvc5

python3 -m venv .venv
.venv/bin/pip install certora-cli==8.17.1 solc-select
.venv/bin/solc-select install 0.8.35
.venv/bin/solc-select use 0.8.35
pnpm install --frozen-lockfile

curl -fL https://github.com/Certora/CertoraProver/releases/download/8.17.1/certora-prover-8.17.1.jar \
  -o /tmp/certora-prover.jar
echo "fe1c68bb6b24140f825abed2d6b45793525bea2bd982c5e576991928bb06d6e3  /tmp/certora-prover.jar" \
  | sha256sum --check

git clone --depth 1 --branch 8.17.1 \
  https://github.com/Certora/CertoraProver.git /tmp/CertoraProver
test "$(git -C /tmp/CertoraProver rev-parse HEAD)" = \
  aeb463b2b88d45900c60fd94d44908622994f04d
cargo generate-lockfile --manifest-path /tmp/CertoraProver/fried-egg/Cargo.toml
echo "680dfe879e52c883207bcbda848613f1091d2eed013f37c7775b92bb7c1b7899  /tmp/CertoraProver/fried-egg/Cargo.lock" \
  | sha256sum --check
cargo build --release --locked --manifest-path /tmp/CertoraProver/fried-egg/Cargo.toml

PATH="/tmp/CertoraProver/fried-egg/target/release:$PATH" \
  .venv/bin/certoraRun certora/conf/StakeQuantileTree.conf \
  --jar /tmp/certora-prover.jar
```

Use `--rule <rule-name>` for a focused run. The release JAR is checksum-pinned and the optimizer source is commit-pinned in the CI workflow.
