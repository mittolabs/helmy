# Contributing to Helmy

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Report a bug or suggest an idea

Use [the issue forms](https://github.com/mittolabs/helmy/issues/new/choose). For a security problem, see [SECURITY.md](SECURITY.md) instead.

## Make a change

1. Read [CLAUDE.md](CLAUDE.md). It has the rule everything in Helmy follows, the two principles every change is judged by, and how the repository is laid out.
2. Set up once, with [fvm](https://fvm.app) installed (and Xcode, to build for macOS):

   ```sh
   make setup
   ```

3. Make your change on a branch, with a test for new behavior.
4. Check it:

   ```sh
   make test
   make analyze
   make format
   ```

5. Open a pull request. Its title is a [Conventional Commit](https://www.conventionalcommits.org/), such as `feat(chats): …` or `fix(phone): …`, with the scope naming the feature, not a file.

`main` only takes changes through pull requests, and a pull request merges once its checks pass.

## License

By contributing, you agree that your work is released under the [BSD 3-Clause License](LICENSE).
