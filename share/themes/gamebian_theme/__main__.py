"""Entry point for `python3 -m gamebian_theme` and setuptools console_scripts."""

from gamebian_theme.app import main as _run


def main() -> None:
    _run()


if __name__ == "__main__":
    main()
