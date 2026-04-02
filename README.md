# PDF Hunter 🔍

A local tool that crawls any website and downloads all PDF files — no CORS issues because it runs server-side.

## Setup (one time)

```bash
pip3 install requests beautifulsoup4
```

## Run

```bash
python3 server.py
```

Then open **http://localhost:7734** in your browser.

## How to use

1. Paste the URL of the site (e.g. `https://www.physicsandmathstutor.com/computer-science-revision/a-level-ocr/`)
2. Set depth (2 = follows links 2 levels deep, 3 = deeper crawl, use 4-5 for big sites)
3. Keep "Same domain only" checked unless you want to crawl external links too
4. Hit **Scan** — the terminal shows live progress
5. **Download All** to grab everything, or download individually

## Tips

- For **PMT / Physics&Maths Tutor**: depth 2 gets everything
- For bigger sites: depth 3, be patient
- The filter box lets you search by filename (e.g. "notes", "past paper", "topic")
- "Copy Links" gives you a list to paste into a download manager like JDownloader

## Requirements

- Python 3.7+
- `requests` and `beautifulsoup4` (auto-installs on first run if missing)
