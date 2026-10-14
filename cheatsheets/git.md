# Git — fiche mémo

```bash
# État et historique
git status -sb                         git log --oneline --graph --all -20
git diff / --staged / main...HEAD      git show <sha> --stat
git blame -L 10,30 fichier             git log -S "texte" --oneline      # qui a ajouté/supprimé ce texte

# Branches
git switch -c feat/x                   git switch main
git branch -vv                         git branch -d feat/x   (-D : forcer)
git push -u origin feat/x              git push origin --delete feat/x

# Intégrer
git pull --rebase                      git merge --no-ff feat/x
git rebase main                        git rebase -i HEAD~5      # squash/fixup/reword/drop
git rebase --continue | --abort        git cherry-pick <sha>

# Annuler
git restore fichier                    git restore --staged fichier
git commit --amend --no-edit           git revert <sha>            # sûr sur une branche partagée
git reset --soft HEAD~1                git reset --hard origin/main   # ⚠ perd le travail local
git reflog                             git reset --hard HEAD@{2}   # sauvetage

# Mettre de côté
git stash push -m "wip"                git stash list / pop / drop

# Tags
git tag -a v1.2.0 -m "msg"             git push --tags

# Enquête
git bisect start; git bisect bad; git bisect good <sha>; git bisect run ./test.sh; git bisect reset

# Pousser après réécriture de SA branche
git push --force-with-lease
```

Conventional Commits : `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `test`, `perf`, `build` ; `!` = breaking change.

`gh` : `gh pr create --fill` · `gh pr checks` · `gh pr merge --squash --delete-branch` · `gh run watch` · `gh run view --log-failed` · `gh issue create`.
