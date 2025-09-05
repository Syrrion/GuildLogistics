# Changelog
Toutes les modifications notables de ce projet seront documentées dans ce fichier.

Le format est basé sur [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
et ce projet adhère au [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## Cleanup
- Suppression anciens workflows redondants
## ⚙️ Miscellaneous Tasks
- Update .pkgmeta with current addon list [skip ci]- Update release workflow to include -z option for packager and add .pkgmeta file- Update workflow permissions to include actions write access- Clean workspace before packaging and simplify .pkgmeta ignore rules- Simplify packaging process by cleaning workspace and updating .pkgmeta ignore rules- Update .pkgmeta with current addon list [skip ci]- Remove update-pkgmeta workflow file- Update .pkgmeta to refine ignore rules and remove manual changelog entry- Update version to 2.7.0 in GuildLogistics.toc and add .gitignore for VS Code settings- Remove settings.json to clean up unused configuration- Enhance auto-release workflow to include changelog generation and PR creation- Update interface version in GuildLogistics.toc to remove deprecated version- Update CHANGELOG for v2.7.2- Update version to 2.7.5 in GuildLogistics.toc and adjust auto-release args- Update version to 2.7.6 in GuildLogistics.toc and enhance auto-release workflow with debug steps- Update version to 2.7.7 in GuildLogistics.toc and adjust auto-release workflow for tag reference- Update version to 2.7.0 in GuildLogistics.toc
## ✨ Features
- Release version 2.7.1- V2.7.14 - Test nouvelle approche workflows séparés- V2.7.15 - Workflow unifié pour release automatique- V2.7.17 - Test workflow avec PAT
## 🐛 Bug Fixes
- Simplify BigWigs Packager arguments- Add tag propagation wait and force overwrite- Complete workflow rewrite with tag creation before packaging- Recréation des workflows corrects
