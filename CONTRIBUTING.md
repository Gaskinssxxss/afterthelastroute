# Contributing

1. Make focused changes and keep topology resource names scoped to `routing-lab`.
2. Run `make lint` and `make preflight` where supported.
3. For routing changes, run the real integration acceptance suite on a disposable compatible Linux host and include redacted evidence. Do not claim integration success from static checks.
4. Never commit credentials, private keys, generated evidence containing sensitive host data, or runtime state.
5. Keep changes to host networking, global Docker settings, and unrelated resources out of scope.

By submitting a contribution, you agree it may be distributed under the repository's MIT license. Do not submit material you are not authorized to license.
