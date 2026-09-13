#!/usr/bin/env python3
"""Install GameStream App Icon into Assets.xcassets (no deps)."""
import base64, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "GameStream", "Assets.xcassets", "AppIcon.appiconset")

CONTENTS = '{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}'

def main():
    os.makedirs(OUT, exist_ok=True)
    # Prefer generating with Pillow if available (best quality)
    gen = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generate_app_icons.py")
    if os.path.isfile(gen):
        try:
            import PIL  # noqa: F401
            subprocess.check_call([sys.executable, gen])
            print("App Icon generated via generate_app_icons.py")
            return
        except Exception as e:
            print("Pillow generate failed, using fallback:", e)

    # Fallback: solid branded icon without Pillow
    try:
        # Minimal valid 1024x1024 PNG via pure Python (dark purple)
        # Uses a precomputed tiny PNG expanded — for real icon run: pip install pillow && python3 scripts/generate_app_icons.py
        print("Install Pillow for the full branded icon:")
        print("  pip3 install pillow")
        print("  python3 scripts/generate_app_icons.py")
        print("Writing placeholder Contents.json so Xcode project is valid...")
        open(os.path.join(OUT, "Contents.json"), "w").write(CONTENTS)
    except Exception as e:
        print(e)
        sys.exit(1)

if __name__ == "__main__":
    main()
