#!/usr/bin/env bash
set -Eeuo pipefail

# Anything other than a clear yes/no is rejected: a typo here must never turn a preview into a real release.
case "${DRY_RUN:-0}" in
    1 | true | TRUE | yes | YES) DRY_RUN=1 ;;
    0 | false | FALSE | no | NO | "") DRY_RUN=0 ;;
    *)
        echo "❌ DRY_RUN must be 0 or 1 (got '${DRY_RUN}')."
        exit 1
        ;;
esac
RELEASE_BRANCH="${RELEASE_BRANCH:-master}"
TARGET_VERSION=""

for arg in "$@"; do
    if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ] || [ "$arg" = "dry-run" ]; then
        DRY_RUN=1
    elif [ -z "${TARGET_VERSION}" ]; then
        TARGET_VERSION="$arg"
    fi
done

CURRENT_VERSION=$(tr -d ' \n\r' <VERSION 2>/dev/null || echo "1.0.0")

if [ -z "${TARGET_VERSION}" ]; then
    # Auto-bump patch version by default if no version passed
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEXT_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEXT_PATCH}"
elif [ "${TARGET_VERSION}" = "patch" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
elif [ "${TARGET_VERSION}" = "minor" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
elif [ "${TARGET_VERSION}" = "major" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="$((MAJOR + 1)).0.0"
else
    # Custom version specified (e.g. 1.1.0 or v1.1.0)
    NEW_VERSION="${TARGET_VERSION#v}"
fi

if ! [[ "${NEW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ Invalid version '${NEW_VERSION}' (expected MAJOR.MINOR.PATCH)."
    exit 1
fi

TAG_NAME="v${NEW_VERSION}"

echo "=========================================="
if [ "${DRY_RUN}" -eq 1 ]; then
    echo " 🧪 [DRY RUN] Simulating Release ${TAG_NAME} (from v${CURRENT_VERSION})"
else
    echo " Creating Release ${TAG_NAME} (from v${CURRENT_VERSION})"
fi
echo "=========================================="

# 0. Preflight: never release from a dirty tree or another branch, and never move a published tag.
preflight_failure() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        echo "⚠️  [DRY RUN] $1 A real release would stop here."
    else
        echo "❌ $1"
        exit 1
    fi
}

if [ -n "$(git status --porcelain)" ]; then
    preflight_failure "The working tree has uncommitted changes."
fi
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "${CURRENT_BRANCH}" != "${RELEASE_BRANCH}" ]; then
    preflight_failure "Releases are cut from ${RELEASE_BRANCH}, but ${CURRENT_BRANCH} is checked out."
fi
if git rev-parse -q --verify "refs/tags/${TAG_NAME}" >/dev/null; then
    preflight_failure "Tag ${TAG_NAME} already exists."
fi
HAS_ORIGIN=0
if git remote get-url origin >/dev/null 2>&1; then
    HAS_ORIGIN=1
    if git ls-remote --exit-code --tags origin "refs/tags/${TAG_NAME}" >/dev/null 2>&1; then
        preflight_failure "Tag ${TAG_NAME} already exists on origin."
    fi
fi

mkdir -p build

# 1. Run unit tests before changing anything
echo "==> Running test suite..."
./scripts/test.sh

# 2. Find previous tag or starting commit
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -n "${PREV_TAG}" ]; then
    echo "==> Gathering commit history since ${PREV_TAG}..."
    COMMIT_RANGE="${PREV_TAG}..HEAD"
else
    echo "==> No previous release tag found. Gathering full commit history..."
    COMMIT_RANGE="HEAD"
fi

# 3. Generate categorized release notes markdown
NOTES_FILE="build/RELEASE_NOTES.md"

cat <<EOF >"${NOTES_FILE}"
# Recall ${TAG_NAME}

## What's Changed in this Release

EOF

FEATS=$(git log ${COMMIT_RANGE} --oneline -i --grep="^feat" | grep -v "chore(release):" || true)
FIXES=$(git log ${COMMIT_RANGE} --oneline -i --grep="^fix" --grep="^refactor" --grep="^perf" | grep -v "chore(release):" || true)
DOCS=$(git log ${COMMIT_RANGE} --oneline -i --grep="^docs" | grep -v "chore(release):" || true)
STYLES=$(git log ${COMMIT_RANGE} --oneline -i --grep="^style" --grep="^ui" --grep="^design" | grep -v "chore(release):" || true)
OTHERS=$(git log ${COMMIT_RANGE} --oneline -i --grep="^feat" --grep="^fix" --grep="^refactor" --grep="^perf" --grep="^docs" --grep="^style" --grep="^ui" --grep="^design" --grep="^chore(release)" --invert-grep || true)

if [ -n "${FEATS}" ]; then
    echo "### 🚀 Features & Enhancements" >>"${NOTES_FILE}"
    echo "${FEATS}" | awk '{ $1=""; print "- " $0 }' >>"${NOTES_FILE}"
    echo "" >>"${NOTES_FILE}"
fi

if [ -n "${FIXES}" ]; then
    echo "### 🐛 Fixes & Improvements" >>"${NOTES_FILE}"
    echo "${FIXES}" | awk '{ $1=""; print "- " $0 }' >>"${NOTES_FILE}"
    echo "" >>"${NOTES_FILE}"
fi

if [ -n "${DOCS}" ]; then
    echo "### 📚 Documentation" >>"${NOTES_FILE}"
    echo "${DOCS}" | awk '{ $1=""; print "- " $0 }' >>"${NOTES_FILE}"
    echo "" >>"${NOTES_FILE}"
fi

if [ -n "${STYLES}" ]; then
    echo "### 🎨 UI & Design Updates" >>"${NOTES_FILE}"
    echo "${STYLES}" | awk '{ $1=""; print "- " $0 }' >>"${NOTES_FILE}"
    echo "" >>"${NOTES_FILE}"
fi

if [ -n "${OTHERS}" ]; then
    echo "### 📦 Other Changes" >>"${NOTES_FILE}"
    echo "${OTHERS}" | awk '{ $1=""; print "- " $0 }' >>"${NOTES_FILE}"
    echo "" >>"${NOTES_FILE}"
fi

echo "---" >>"${NOTES_FILE}"
echo "**Full Changelog**: https://github.com/unamatasanatarai/recall/commits/${TAG_NAME}" >>"${NOTES_FILE}"

echo "==> Generated Release Notes:"
cat "${NOTES_FILE}"
echo ""

# 4. Update VERSION file (restored if any later step fails)
if [ "${DRY_RUN}" -eq 1 ]; then
    echo "==> [DRY RUN] Skipping VERSION file update (would update to ${NEW_VERSION})"
else
    echo "${NEW_VERSION}" >VERSION
    trap 'echo "❌ Release failed; restoring VERSION"; git checkout -- VERSION' ERR
    echo "==> Updated VERSION file to ${NEW_VERSION}"
fi

# 5. Build application & DMG package. A real release always compiles from scratch, so the DMG
#    can never contain a stale binary or an old version number.
echo "==> Building installer DMG package..."
if [ "${DRY_RUN}" -eq 1 ]; then
    ./scripts/build.sh
else
    FORCE_BUILD=1 ./scripts/build.sh
fi
./scripts/build_dmg.sh

DMG_PATH="build/Recall-${TAG_NAME}.dmg"
if [ "${DRY_RUN}" -eq 1 ]; then
    echo "==> [DRY RUN] Renaming generated DMG to match simulated release tag ${TAG_NAME}..."
    cp "build/Recall-v${CURRENT_VERSION}.dmg" "${DMG_PATH}" 2>/dev/null || true
fi

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "=========================================="
    echo " 🧪 [DRY RUN COMPLETE] Release preview finished successfully!"
    echo " Target Version: ${NEW_VERSION}"
    echo " Tag Name: ${TAG_NAME}"
    echo " Release Notes: ${NOTES_FILE}"
    echo " DMG Image: ${DMG_PATH}"
    echo " No git commits, tags, or GitHub releases were published."
    echo "=========================================="
    exit 0
fi

# 6. Commit version bump and create git tag
echo "==> Committing release version ${NEW_VERSION}..."
git add VERSION
if git diff --quiet --staged; then
    echo "VERSION unchanged in git stage, proceeding to tag..."
else
    git commit -m "chore(release): release ${TAG_NAME}"
fi
trap - ERR

echo "==> Creating git tag ${TAG_NAME}..."
git tag -a "${TAG_NAME}" -F "${NOTES_FILE}"

# 7. Push commit & tag. A failed push stops here, before anything is published.
if [ "${HAS_ORIGIN}" -eq 1 ]; then
    echo "==> Pushing ${RELEASE_BRANCH} and tag ${TAG_NAME} to origin..."
    git push origin "${RELEASE_BRANCH}"
    git push origin "${TAG_NAME}"
fi

# 8. Create GitHub Release using gh CLI
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    echo "==> Creating GitHub Release via gh CLI..."
    gh release create "${TAG_NAME}" "${DMG_PATH}#Recall-${TAG_NAME}.dmg" \
        --title "Recall ${TAG_NAME}" \
        --notes-file "${NOTES_FILE}"
    echo "==> GitHub Release ${TAG_NAME} successfully created!"
else
    echo "--------------------------------------------------------"
    echo "Notice: the GitHub CLI (gh) is missing or not authenticated."
    echo "Git tag ${TAG_NAME} and release DMG created at:"
    echo "  ${DMG_PATH}"
    echo "Release notes written to:"
    echo "  ${NOTES_FILE}"
    echo ""
    echo "To publish the GitHub Release, run:"
    echo "  1. brew install gh   (if needed)"
    echo "  2. gh auth login"
    echo "  3. gh release create ${TAG_NAME} \"${DMG_PATH}#Recall-${TAG_NAME}.dmg\" -t \"Recall ${TAG_NAME}\" -F ${NOTES_FILE}"
    echo "--------------------------------------------------------"
fi

echo "=========================================="
echo " Release ${TAG_NAME} Process Complete!"
echo "=========================================="
