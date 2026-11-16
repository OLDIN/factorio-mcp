#!/usr/bin/env python3
"""Generate a bearer token. Prints the token once and a tokens.toml entry holding only its hash."""

import argparse
import hashlib
import secrets


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="person's name")
    parser.add_argument("--nick", required=True, help="in-game nickname")
    args = parser.parse_args()
    token = secrets.token_urlsafe(32)
    digest = hashlib.sha256(token.encode()).hexdigest()
    print(f"Token (shown once, give it to {args.name}):\n{token}\n")
    print("Add to tokens.toml:")
    print(f'[[token]]\nname = "{args.name}"\nnick = "{args.nick}"\nsha256 = "{digest}"')


if __name__ == "__main__":
    main()
