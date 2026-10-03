#!/usr/bin/env bash
set -euo pipefail

CURRENT_VERSION=$(tr -d ' \n\r' <VERSION 2>/dev/null || echo "1.0.0")

# Determine target version
TARGET_ARG="${1:-}"

if [ -z "${TARGET_ARG}" ]; then
    # Auto-bump patch version by default if no version passed
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEXT_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEXT_PATCH}"
elif [ "${TARGET_ARG}" = "patch" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
elif [ "${TARGET_ARG}" = "minor" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
elif [ "${TARGET_ARG}" = "major" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<<"${CURRENT_VERSION}"
    NEW_VERSION="$((MAJOR + 1)).0.0"
else
    # Custom version specified (e.g. 1.1.0 or v1.1.0)
    NEW_VERSION="${TARGET_ARG#v}"
fi

TAG_NAME="v${NEW_VERSION}"

echo "=========================================="
echo " Creating Release ${TAG_NAME} (from v${CURRENT_VERSION})"
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

FEATS=$(git log ${COMMIT_RANGE} --oneline -i --grep="^feat" || true)
FIXES=$(git log ${COMMIT_RANGE} --oneline -i --grep="^fix" --grep="^refactor" --grep="^perf" || true)
STYLES=$(git log ${COMMIT_RANGE} --oneline -i --grep="^style" --grep="^ui" --grep="^design" || true)
OTHERS=$(git log ${COMMIT_RANGE} --oneline -i --grep="^feat" --grep="^fix" --grep="^refactor" --grep="^perf" --grep="^style" --grep="^ui" --grep="^design" --invert-grep || true)

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
echo "${NEW_VERSION}" >VERSION
echo "==> Updated VERSION file to ${NEW_VERSION}"

# 4. Run unit tests
echo "==> Running test suite..."
./test.sh

# 5. Build application & DMG package
echo "==> Building installer DMG package..."
./create_dmg.sh

DMG_PATH="build/Recall-${TAG_NAME}.dmg"
if [ ! -f "${DMG_PATH}" ]; then
    echo "Error: DMG file ${DMG_PATH} not found!"
    exit 1
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

# 8. Create GitHub Release using gh CLI (or provide login instructions if not authenticated)
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
