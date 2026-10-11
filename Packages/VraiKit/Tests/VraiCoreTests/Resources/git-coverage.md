# Git coverage

Every command in `git help -a` (git 2.54) has a home. Everyday porcelain lives on the surface; options live one step down in a Disclosure, behind the Option key or in Expert mode; plumbing runs in the console and powers the views. The command palette (⌘K) finds every action below by name, and in Expert mode runs anything typed after `git`.

Where a cell says **menu**, it means the macOS menu bar and the matching context menu. **Console** means the drawer (⌘J), where any command runs and every command Vrai runs is logged.

## Main porcelain

| Command | Home | How it works |
|---|---|---|
| `add` | Changes | Check a file or press Space; stage a hunk from its header, or select lines in the gutter and stage them. Option turns Stage all into `git add -A`. Expert: Intent to add in the file menu. |
| `am` | Repository menu, Apply patches | A sheet takes mbox or patch files with three-way and sign-off options; a stop shows the same banner as a rebase. |
| `archive` | Commit and tag menus, Export archive | A sheet picks zip or tar.gz, a prefix and a path filter. |
| `backfill` | Repository menu, Maintenance (Expert) | Fetches missing blobs in a partial clone. Shown only for partial clones. |
| `bisect` | Commit menu, Start bisect here | A banner with Good, Bad, Skip and End; the graph marks each tested commit. Expert: run a test script, view the bisect log. |
| `branch` | Sidebar, Branches; New branch (⇧⌘B) | Create, rename, delete with Undo, set upstream. Expert filters: merged into HEAD, contains a commit. |
| `bundle` | Repository menu, Create bundle; Clone sheet | Writes a bundle of chosen refs; Clone accepts a bundle file as its source. |
| `checkout` | History and sidebar | Double-click a commit or tag to look at it in detached HEAD, with a banner. Vrai uses `switch` and `restore` for everything else. |
| `cherry-pick` | Commit menu; drag a commit onto HEAD | Options: record origin (`-x`), apply without committing, mainline for merges. Several selected commits pick in order. |
| `citool` | Changes | The Changes view replaces it. |
| `clean` | Changes, untracked group menu | Remove untracked files lists them first as a dry run. Expert adds ignored files (`-x`). |
| `clone` | Welcome window; File menu | URL, location, branch, submodules. Options: depth, partial clone filter, bare, mirror. Progress shows objects and speed. |
| `commit` | Changes composer (⌘↩) | Commit and push (⌥⌘↩), amend, sign-off, skip hooks, signing, trailers. Expert: Create fixup commit for a selected commit. |
| `describe` | Commit detail | The inspector shows `v0.9.1-4-ge41c9a2` beside the hash. |
| `diff` | Every diff | Working tree, staged, a commit, any two selected commits, two branches. Unified or split, whitespace, word diff. Expert: diff algorithm, rename detection threshold. |
| `fetch` | Toolbar (⇧⌘F); background fetch | Option fetches all remotes with prune. The Fetch sheet: prune, tags, depth, unshallow. |
| `format-patch` | Commit menu, Save as patch | Several selected commits save as a numbered series. |
| `gc` | Repository menu, Maintenance, Clean up | Expert: aggressive, prune now. |
| `gitk` | History | The History view replaces it. |
| `grep` | Command palette, Search code | Searches tracked files at HEAD or any revision; results open the file at the line. |
| `gui` | Vrai | Vrai replaces it. |
| `history` | Commit menu, Reword and Split (Expert) | `git history reword` and `git history split` edit a commit without a full rebase when git is 2.54 or later. |
| `init` | Welcome window; File menu | Location, initial branch name, a .gitignore template. |
| `log` | History | The graph; filters for branch scope, author, path, dates and message. Expert: first parent only, pickaxe (`-S`, `-G`), any revision range. |
| `maintenance` | Settings, Repository | Background maintenance switch; Run now in the Maintenance menu. |
| `merge` | Toolbar, Merge (⇧⌘M); drag a branch onto HEAD | Fast-forward, merge commit or squash; message. Expert: fast-forward only, strategy and its options. The sheet predicts conflicts before you start. |
| `mv` | File menu, Rename | Renames and stages in one step. |
| `notes` | Commit detail, Notes (Expert) | Add, edit and remove a note; notes refs list under Refs. |
| `pull` | Toolbar (⇧⌘L) | Option pulls with rebase. Settings choose merge, rebase or fast-forward only, and autostash. |
| `push` | Toolbar (⇧⌘P) | Option force pushes with lease. The Push sheet: remote, branch, set upstream, tags, push options, skip hooks. |
| `range-diff` | After a rebase; branch menu (Expert) | Compare with before shows how each commit changed across the rebase. |
| `rebase` | Toolbar, Rebase (⇧⌘R); Interactive rebase | Reorder by drag or ⌥↑ ⌥↓, pick, reword, edit, squash, fixup, drop. Options: autosquash, update refs. Expert: onto a third base. A banner continues, skips or aborts. |
| `reset` | Commit menu, Reset branch to here | Cards for soft, mixed, hard and keep say what each does to your files. Hard keeps a copy in Undo history. |
| `restore` | File and hunk menus | Discard changes, unstage, restore a file from any commit. |
| `revert` | Commit menu, Revert commit | Options: without committing, mainline for merges. |
| `rm` | File menu | Delete file, or Stop tracking (`--cached`). |
| `scalar` | Clone sheet, Large repository (Expert) | Clones with scalar's defaults and registers the repository for maintenance. |
| `shortlog` | History, Author filter | The author menu lists contributors with their commit counts. |
| `show` | Commit detail; tag popover | Open file at this commit shows any blob at any revision. |
| `sparse-checkout` | Repository menu, Sparse checkout (Expert) | A folder tree picks what to check out; the title shows a Sparse badge. |
| `stash` | Toolbar, Stash (⇧⌘S); Stashes (⌘3) | Message, include untracked, keep staged, stash only staged. Apply, pop, drop with Undo, create a branch from a stash. |
| `status` | Changes; sidebar counts | Always live. |
| `submodule` | Sidebar, Submodules | Add, init, update, sync, deinit; each row shows its state against the recorded commit. |
| `switch` | Double-click a branch; palette, Switch to | With changes in the way, the alert offers to bring them along or stash them. |
| `tag` | Sidebar, Tags; commit menu, New tag | Lightweight, annotated or signed; push to a remote; delete locally or on the remote. |
| `worktree` | Sidebar, Worktrees | Add for a branch, open in a new window, lock, remove. Expert: prune. |

## Ancillary commands

| Command | Home | How it works |
|---|---|---|
| `config` | Settings | Git pane for identity, signing and tools; Repository pane for this repository. Expert: a config table across system, global, local and worktree scopes. |
| `fast-export`, `fast-import` | Console | Kept for scripted migrations. |
| `filter-branch` | Console | Not in the interface: git itself deprecates it. The console warns and links to `git filter-repo`. |
| `mergetool`, `difftool` | Settings, Tools; file menu | Choose an external tool; Open in merge tool or diff tool on any file. |
| `pack-refs`, `prune`, `repack` | Repository menu, Maintenance (Expert) | Part of Clean up, or one at a time. |
| `reflog` | Edit menu, Undo history; sidebar, Reflog (Expert) | Undo history lists what Vrai can restore in plain words; Reflog shows every ref movement with Restore. |
| `refs` | Sidebar, Refs (Expert) | Every ref by namespace; verify and migrate run in the console. |
| `remote` | Sidebar, Remotes | Add, edit URLs, rename, remove, prune, set HEAD. |
| `replace` | Sidebar, Refs, Replacements (Expert) | Lists replacement refs; create and delete from the commit menu. |
| `annotate`, `blame` | File menu, Blame | Each line with its commit, author and age; Blame before this change steps back. |
| `bugreport`, `diagnose` | Help menu, Report a git problem | Collects both into a folder you can attach. |
| `count-objects` | Repository menu, Repository info | Size, objects, packs and loose objects. |
| `fsck` | Repository menu, Maintenance, Verify integrity | Lists dangling and broken objects. |
| `gitweb`, `instaweb` | Console | Not in the interface: they start web servers. |
| `help` | Help menu, Git reference | Opens the manual page for any command; ⌥-click a command preview to open its page. |
| `merge-tree` | Merge sheet | Predicts conflicts before a merge starts. |
| `rerere` | Settings, Git, Reuse recorded resolutions | The conflict view says when a resolution was replayed. |
| `show-branch` | Console | Branch compare in History covers it. |
| `verify-commit`, `verify-tag` | Signature badges | Rows and the detail show verified, unknown key, bad or unsigned; click to see the signer. |
| `version` | Settings, Git | Shows the git in use and its path. |
| `whatchanged` | History | The commit detail lists files; git deprecates the command. |

## Interacting with others

| Command | Home | How it works |
|---|---|---|
| `request-pull` | Branch menu, Copy pull request summary (Expert) | Copies the summary to the clipboard. |
| `send-email`, `imap-send` | Save as patch sheet (Expert) | Saves the series and copies the matching `send-email` command. |
| `archimport`, `cvsexportcommit`, `cvsimport`, `cvsserver`, `p4`, `quiltimport`, `svn` | Console | Not in the interface: bridges to other version control systems need their own tools. |

## Plumbing

Vrai runs these to draw its views, and each runs by hand in the console.

| Command | Used for |
|---|---|
| `apply` | Line and hunk staging; Repository menu, Apply patch. |
| `cat-file`, `ls-tree`, `show-ref`, `for-each-ref`, `rev-parse`, `name-rev` | The sidebar, the detail inspector, Open file at commit. Expert: Show object. |
| `rev-list`, `merge-base`, `cherry`, `patch-id` | Ahead and behind counts, branch compare, marking commits already picked. |
| `diff-files`, `diff-index`, `diff-tree`, `diff-pairs` | Status, staged and commit diffs. |
| `ls-files`, `check-ignore`, `check-attr` | The file tree; Why is this ignored; binary and LFS markers. |
| `ls-remote` | The branch picker in Clone; Show remote refs. |
| `last-modified` | The last commit beside each file when browsing a tree. |
| `repo` | Repository info. |
| `update-index` | Assume unchanged and skip worktree in the file menu (Expert). |
| `update-ref`, `symbolic-ref` | Undo, Restore from the reflog, editing refs under Refs. |
| `replay` | Rebase in the background without touching the working tree (Expert option in the Rebase sheet). |
| `merge-file`, `merge-index`, `merge-one-file` | Reset a conflict to its merged state. |
| `commit-graph`, `multi-pack-index`, `pack-objects`, `index-pack`, `unpack-objects`, `prune-packed`, `pack-redundant`, `verify-pack`, `show-index` | Maintenance. |
| `hash-object`, `mktag`, `mktree`, `commit-tree`, `write-tree`, `read-tree`, `checkout-index`, `unpack-file`, `get-tar-commit-id` | Console. |
| `for-each-repo` | Background maintenance across registered repositories. |
| `credential`, `credential-cache`, `credential-store` | Settings, Accounts. |
| `check-ref-format` | Validates branch and tag names as you type. |
| `check-mailmap` | Author names in rows and filters follow .mailmap. |
| `fmt-merge-msg`, `stripspace`, `interpret-trailers` | The merge message, commit message cleanup, trailers such as Co-authored-by. |
| `hook` | Settings, Repository, Hooks lists them and runs one by hand. |
| `mailinfo`, `mailsplit` | Apply patches. |
| `var`, `column`, `sh-i18n`, `sh-setup` | Internal; console only. |
| `daemon`, `fetch-pack`, `send-pack`, `http-backend`, `update-server-info` | Server side; console only. |

## Files and syntax

| Interface | Home |
|---|---|
| `.gitignore` | File menu, Ignore this file or Ignore all `.ext` files; Repository menu, Edit .gitignore. |
| `.gitattributes` | Repository menu, Edit .gitattributes (Expert). |
| `.mailmap` | Repository menu, Edit .mailmap (Expert). |
| `.gitmodules` | Sidebar, Submodules. |
| Hooks | Settings, Repository, Hooks. |
| Revisions | The palette and every revision field accept git's syntax: `main~3`, `HEAD@{2}`, `v0.9.0..main`, `:/graph`. |
