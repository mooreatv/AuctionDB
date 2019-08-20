#! /usr/bin/bash
# Get latest tag and switch TOC and retag and switch back
# Until curse or wow supports something less painful
# https://authors.curseforge.com/forums/world-of-warcraft/general-chat/general-chat/239432-classic-vs-bfa-addon-versions-branching-tags
# https://authors.curseforge.com/forums/world-of-warcraft/general-chat/updaters/240327-classic-vs-bfa-interface-toc-versions

# TOC Versions
RETAIL_TOC_V=80200
CLASSIC_TOC_V=11302

git fetch && git pull

TAG=`git describe --tags`
if [[ $TAG == *"classic"* ]]; then
    echo "Error: the latest tag is already classic: $TAG"
    exit 1
fi
if [ -n "$(git status --porcelain)" ]; then 
    echo "Error: directory tree is not clean:"
    git status
    exit 1
fi
TOC_FILES=$(ls *.toc */*.toc 2> /dev/null)
echo "Processing TOC file(s): $TOC_FILES"
sed -i -e "s/## Interface:.*/## Interface: $CLASSIC_TOC_V/" $TOC_FILES
git commit -a -m "Switching to classic toc $CLASSIC_TOC_V for $TAG-classic"
git tag ${TAG}-classic
git push && git push --tags
sed -i -e "s/## Interface:.*/## Interface: $RETAIL_TOC_V/" $TOC_FILES
git commit -a -m "Switching back to retail toc $RETAIL_TOC_V"
git push
