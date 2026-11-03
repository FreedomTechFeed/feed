"""Guard rails for the SDK image pins in .github/workflows/validate-feed.yml.

These are the executable form of the FE1 acceptance criteria:

  * every `openwrt/sdk` image reference is a release tag AND an explicit
    manifest digest (`openwrt/sdk:<tag>@sha256:<digest>`) -- never a moving
    `-master` / `-SNAPSHOT` tag, never a floating major tag;
  * the `feeds install golang<X>` line is driven by the matrix, so the golang
    package always matches the OpenWrt branch of the pinned SDK image.

Run:  python3 -m pytest tests/ -q
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/validate-feed.yml"

# GO_DEFAULT_VERSION of lang/golang/golang-values.mk on each OpenWrt branch
# (openwrt/packages). Source read 2026-11-03:
#   openwrt-25.12 -> 1.26      openwrt-24.10 -> 1.23
GOLANG_BY_BRANCH = {"25.12": "1.26", "24.10": "1.23"}

DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
MOVING_TAG_RE = re.compile(r"-master$|-SNAPSHOT$")
# A bare floating tag such as `openwrt/sdk:25.12` or `:latest` (no `-vX.Y.Z`).
RELEASE_TAG_RE = re.compile(r"-v\d+\.\d+\.\d+$")


@pytest.fixture(scope="module")
def workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text())


@pytest.fixture(scope="module")
def sdk_matrix(workflow) -> list[dict]:
    return workflow["jobs"]["build-sdk"]["strategy"]["matrix"]["include"]


def test_image_reference_is_tag_plus_digest(workflow, sdk_matrix):
    image = workflow["jobs"]["build-sdk"]["container"]["image"]
    assert "@" in image, f"container image is not digest-pinned: {image!r}"
    tag_part, digest = image.rsplit("@", 1)
    assert tag_part.startswith("openwrt/sdk:"), f"unexpected image: {image!r}"
    if "${{" in digest:  # matrix-driven: every row must then carry a real digest
        assert digest == "${{ matrix.digest }}", digest
        for row in sdk_matrix:
            assert DIGEST_RE.match(row["digest"]), f"bad row digest: {row['digest']!r}"
    else:
        assert DIGEST_RE.match(digest), f"bad digest: {digest!r}"


def test_no_moving_or_floating_tags_anywhere_in_workflow():
    text = WORKFLOW.read_text()
    for line in text.splitlines():
        if "openwrt/sdk" in line and not line.lstrip().startswith("#"):
            assert not MOVING_TAG_RE.search(line), f"moving tag: {line.strip()!r}"


def test_every_matrix_row_pins_tag_digest_branch_golang(sdk_matrix):
    assert len(sdk_matrix) == 3, sdk_matrix
    for row in sdk_matrix:
        for key in ("target", "tag", "digest", "branch", "golang"):
            assert key in row, f"matrix row missing {key!r}: {row}"
        assert RELEASE_TAG_RE.search(row["tag"]), f"not a release tag: {row['tag']!r}"
        assert not MOVING_TAG_RE.search(row["tag"]), row["tag"]
        assert row["tag"].startswith(f"{row['target']}-"), (
            f"tag {row['tag']!r} does not belong to target {row['target']!r}"
        )
        assert DIGEST_RE.match(row["digest"]), row["digest"]


def test_container_image_consumes_the_matrix_pin(workflow):
    image = workflow["jobs"]["build-sdk"]["container"]["image"]
    assert "${{ matrix.tag }}" in image, image
    assert "${{ matrix.digest }}" in image, image


def test_golang_install_line_is_matrix_driven():
    steps = WORKFLOW.read_text()
    install = [ln for ln in steps.splitlines() if "feeds install" in ln]
    assert install, "no feeds install line found"
    line = install[0]
    assert "${{ matrix.golang }}" in line, f"golang not matrix-driven: {line.strip()!r}"
    # No hardcoded golang1.XX left on the install line.
    assert not re.search(r"golang\d+\.\d+", line), f"hardcoded golang: {line.strip()!r}"


def test_golang_matches_pinned_branch(sdk_matrix):
    for row in sdk_matrix:
        assert row["branch"] in GOLANG_BY_BRANCH, f"unknown branch {row['branch']!r}"
        assert row["golang"] == GOLANG_BY_BRANCH[row["branch"]], (
            f"{row['target']}: branch {row['branch']} needs golang "
            f"{GOLANG_BY_BRANCH[row['branch']]}, matrix says {row['golang']}"
        )


def test_cache_key_carries_the_pinned_version(workflow):
    """A cache built against another toolchain poisons the build (2026-09-08)."""
    cache = next(
        s for s in workflow["jobs"]["build-sdk"]["steps"]
        if s.get("uses", "").startswith("actions/cache")
    )
    tag = workflow["jobs"]["build-sdk"]["strategy"]["matrix"]["include"][0]["tag"]
    version = tag.rsplit("-v", 1)[1]
    assert version in cache["with"]["key"], cache["with"]["key"]
    assert version in cache["with"]["restore-keys"], cache["with"]["restore-keys"]
