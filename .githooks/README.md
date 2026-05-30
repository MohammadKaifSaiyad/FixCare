# .githooks

Committed git hooks for FixCare. Activated per-clone (git does not auto-enable a
committed hooks dir) with:

```sh
git config core.hooksPath .githooks
```

Run that once after cloning. (Already set on the original machine.)

## Hooks

- **`commit-msg`** — rejects any commit whose message contains a
  `Co-Authored-By: Claude` trailer, or whose author email is not
  `saiyedkgn6@gmail.com`. See [memory: commit authorship] and the project's
  commit identity in local git config (`user.name=MohammadKaifSaiyad`,
  `user.email=saiyedkgn6@gmail.com`).
