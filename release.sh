#!/usr/bin/env bash
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
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

TAG_NAME="v${NEW_VERSION}"

echo "=========================================="
if [ "${DRY_RUN}" -eq 1 ]; then
    echo " 🧪 [DRY RUN] Simulating Release ${TAG_NAME} (from v${CURRENT_VERSION})"
else
    echo " Creating Release ${TAG_NAME} (from v${CURRENT_VERSION})"
fi
echo "=========================================="

mkdir -p build

# 1. Find previous tag or starting commit
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [ -n "${PREV_TAG}" ]; then
    echo "==> Gathering commit history since ${PREV_TAG}..."
    COMMIT_RANGE="${PREV_TAG}..HEAD"
else
    echo "==> No previous release tag found. Gathering full commit history..."
    COMMIT_RANGE="HEAD"
fi

# 2. Generate categorized release notes markdown
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

# 3. Update VERSION file
if [ "${DRY_RUN}" -eq 1 ]; then
    echo "==> [DRY RUN] Skipping VERSION file update (would update to ${NEW_VERSION})"
else
    echo "${NEW_VERSION}" >VERSION
    echo "==> Updated VERSION file to ${NEW_VERSION}"
fi

# 4. Run unit tests
echo "==> Running test suite..."
./test.sh

# 5. Build application & DMG package
echo "==> Building installer DMG package..."
./create_dmg.sh

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

echo "==> Creating git tag ${TAG_NAME}..."
git tag -a "${TAG_NAME}" -F "${NOTES_FILE}" --force

# 7. Push git tag & commit to GitHub remote
if git remote get-url origin >/dev/null 2>&1; then
    echo "==> Pushing commits and tag ${TAG_NAME} to GitHub origin..."
    git push origin master || true
    git push origin "${TAG_NAME}" --force || true
fi

# 8. Create GitHub Release using gh CLI
if ! command -v gh &>/dev/null; then
    if command -v brew &>/dev/null; then
        echo "==> GitHub CLI (gh) not found. Installing via Homebrew..."
        NONINTERACTIVE=1 brew install gh || true
    fi
fi

if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    echo "==> Creating GitHub Release via gh CLI..."
    gh release create "${TAG_NAME}" "${DMG_PATH}#Recall-${TAG_NAME}.dmg" \
        --title "Recall ${TAG_NAME}" \
        --notes-file "${NOTES_FILE}"
    echo "==> GitHub Release ${TAG_NAME} successfully created!"
else
    echo "--------------------------------------------------------"
    echo "Notice: 'gh' CLI tool is not authenticated."
    echo "Git tag ${TAG_NAME} and release DMG created at:"
    echo "  ${DMG_PATH}"
    echo "Release notes written to:"
    echo "  ${NOTES_FILE}"
    echo ""
    echo "To authenticate and create the GitHub Release, run:"
    echo "  1. gh auth login"
    echo "  2. gh release create ${TAG_NAME} \"${DMG_PATH}#Recall-${TAG_NAME}.dmg\" -t \"Recall ${TAG_NAME}\" -F ${NOTES_FILE}"
    echo "--------------------------------------------------------"
fi

echo "=========================================="
echo " Release ${TAG_NAME} Process Complete!"
echo "=========================================="
