#!/usr/bin/env python3
"""
PDF Hunter - Local backend server
Run: python3 server.py
Then open: http://localhost:7734
"""

import io
import os
import re
import time
import json
import queue as _queue
import threading
import zipfile
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from collections import deque

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("Installing dependencies...")
    os.system("pip3 install requests beautifulsoup4 --break-system-packages -q")
    import requests
    from bs4 import BeautifulSoup

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-GB,en;q=0.9',
}

MAX_PAGES = 300
N_WORKERS = 12

scan_state = {
    'running': False,
    'logs': deque(maxlen=500),
    'pdfs': [],
    'pages_checked': 0,
    'done': False,
}
scan_lock = threading.Lock()
thread_local = threading.local()


def get_session():
    if not hasattr(thread_local, 'session'):
        s = requests.Session()
        s.headers.update(HEADERS)
        thread_local.session = s
    return thread_local.session


def log(msg, level='info'):
    with scan_lock:
        scan_state['logs'].append({'msg': msg, 'level': level, 't': time.time()})


def reset_state():
    with scan_lock:
        scan_state['running'] = True
        scan_state['logs'] = deque(maxlen=500)
        scan_state['pdfs'] = []
        scan_state['pages_checked'] = 0
        scan_state['done'] = False



def extract_links(html, base_url):
    try:
        soup = BeautifulSoup(html, 'html.parser')
        links = set()
        for tag in soup.find_all(['a', 'link'], href=True):
            href = tag.get('href', '').strip()
            if not href or href.startswith('#') or href.startswith('javascript:') or href.startswith('mailto:'):
                continue
            try:
                abs_url = urllib.parse.urljoin(base_url, href).split('#')[0]
                if abs_url:
                    links.add(abs_url)
            except Exception:
                pass
        for tag in soup.find_all(True):
            for attr in ['src', 'data-src', 'data-href', 'data-url']:
                val = tag.get(attr, '')
                if val and '.pdf' in val.lower():
                    try:
                        links.add(urllib.parse.urljoin(base_url, val).split('#')[0])
                    except Exception:
                        pass
        for p in re.findall(r'https?://[^\s\'"<>]+\.pdf[^\s\'"<>]*', html, re.IGNORECASE):
            links.add(p.split('#')[0])
        return links
    except Exception:
        return set()


def is_pdf(url):
    return url.split('?')[0].lower().endswith('.pdf')


def is_crawlable(url):
    path = url.split('?')[0].lower()
    skip = ('.jpg', '.jpeg', '.png', '.gif', '.svg', '.ico', '.css', '.js',
            '.mp4', '.mp3', '.zip', '.rar', '.gz', '.woff', '.woff2', '.ttf',
            '.xml', '.json', '.csv', '.xlsx', '.docx', '.pptx', '.epub', '.pdf')
    return not any(path.endswith(e) for e in skip)


def url_under_start_path(url, start_path):
    if is_pdf(url):
        return True
    try:
        return urllib.parse.urlparse(url).path.startswith(start_path)
    except Exception:
        return False


def get_path_parts(url):
    """Return decoded path segments from a URL, excluding the filename itself."""
    try:
        path = urllib.parse.urlparse(url).path
        parts = [urllib.parse.unquote(p) for p in path.split('/') if p]
        return parts  # last element is the filename
    except Exception:
        return []


def resolve_display_names(pdfs):
    """
    Always prefix each PDF with its immediate parent folder for context, then
    chain in more ancestors until all names are unique.

    Example:
      .../Notes/Advanced/1.1.1. Structure.pdf     -> "Advanced — 1.1.1. Structure.pdf"
      .../Topic-Qs/Advanced/1.1.1. Structure.pdf  -> "Advanced — 1.1.1. Structure.pdf"
      (still clashes) -> "Notes — Advanced — 1.1.1. Structure.pdf"
                      -> "Topic-Qs — Advanced — 1.1.1. Structure.pdf"
    """
    from collections import Counter

    def make_name(pdf, n_parents):
        parts = get_path_parts(pdf['url'])
        # parts[-1] is filename; use up to n_parents ancestors before it
        if len(parts) > n_parents:
            ancestors = parts[-(n_parents + 1):-1]
            return ' — '.join(ancestors) + ' — ' + pdf['raw_name']
        return pdf['raw_name']

    # Always start with 1 parent for context
    for pdf in pdfs:
        pdf['name'] = make_name(pdf, 1)

    # Expand ancestors until all names are unique
    for n_parents in range(2, 10):
        name_counts = Counter(p['name'] for p in pdfs)
        dupes = {name for name, count in name_counts.items() if count > 1}
        if not dupes:
            break
        for pdf in pdfs:
            if pdf['name'] in dupes:
                pdf['name'] = make_name(pdf, n_parents)


def parse_filter(raw):
    terms = raw.lower().split()
    include = [t for t in terms if not t.startswith('-') and t]
    exclude = [t[1:] for t in terms if t.startswith('-') and len(t) > 1]
    return include, exclude


def name_matches_filter(name, include, exclude):
    n = name.lower()
    return all(t in n for t in include) and not any(t in n for t in exclude)


def do_scan(start_url, max_depth, same_domain, strict_path, name_filter=''):
    reset_state()
    log(f'Starting scan: {start_url}', 'info')

    try:
        parsed_start = urllib.parse.urlparse(start_url)
        base_domain = parsed_start.netloc
        start_path = parsed_start.path.rstrip('/') or '/'
    except Exception:
        log('Invalid URL', 'error')
        with scan_lock:
            scan_state['running'] = False
            scan_state['done'] = True
        return

    if strict_path:
        log(f'Path lock ON — only crawling under: {start_path}/', 'info')
    else:
        log(f'Crawling full domain: {base_domain}', 'info')

    include_terms, exclude_terms = parse_filter(name_filter)
    if include_terms or exclude_terms:
        log(f'Pre-filter active: {name_filter}', 'info')

    found_pdfs = set()
    found_lock = threading.Lock()
    visited = set()
    visited_lock = threading.Lock()
    cap_logged = [False]
    stop_event = threading.Event()
    work_queue = _queue.Queue()
    work_queue.put((start_url, 0))

    def process_url(url, depth):
        with visited_lock:
            if url in visited:
                return
            visited.add(url)

        if is_pdf(url):
            with found_lock:
                if url in found_pdfs:
                    return
                found_pdfs.add(url)
            raw_name = urllib.parse.unquote(url.split('?')[0].rstrip('/').split('/')[-1])
            if (include_terms or exclude_terms) and not name_matches_filter(raw_name, include_terms, exclude_terms):
                log(f'Skipped (filter): {raw_name}')
                return
            with scan_lock:
                scan_state['pdfs'].append({'url': url, 'raw_name': raw_name, 'name': raw_name})
            log(f'PDF: {raw_name}', 'success')
            return

        if not is_crawlable(url) or depth > max_depth:
            return

        try:
            link_domain = urllib.parse.urlparse(url).netloc
            root_domain = '.'.join(base_domain.split('.')[-2:])
        except Exception:
            return

        if same_domain and link_domain != base_domain:
            if root_domain not in link_domain:
                return

        if strict_path and not url_under_start_path(url, start_path):
            return

        with scan_lock:
            if scan_state['pages_checked'] >= MAX_PAGES:
                if not cap_logged[0]:
                    cap_logged[0] = True
                    log(f'Hit {MAX_PAGES} page cap. Try a more specific URL or lower depth.', 'error')
                return
            scan_state['pages_checked'] += 1
        log(f'[{depth}] {url}')

        try:
            r = get_session().get(url, timeout=12, allow_redirects=True)
            r.raise_for_status()
            html = r.text
        except Exception:
            log(f'Failed: {url}', 'error')
            return

        links = extract_links(html, url)
        for link in links:
            with visited_lock:
                if link in visited:
                    continue
            if is_pdf(link):
                work_queue.put((link, depth))
            elif depth < max_depth:
                work_queue.put((link, depth + 1))

    def worker():
        while not stop_event.is_set():
            try:
                url, depth = work_queue.get(timeout=0.5)
            except _queue.Empty:
                continue
            try:
                if scan_state['running']:
                    process_url(url, depth)
            finally:
                work_queue.task_done()

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(N_WORKERS)]
    for t in threads:
        t.start()

    work_queue.join()
    stop_event.set()
    for t in threads:
        t.join(timeout=3)

    with scan_lock:
        resolve_display_names(scan_state['pdfs'])

    if not scan_state['running']:
        log('Stopped by user.', 'error')
    else:
        log(f'Done! {len(found_pdfs)} PDFs found across {scan_state["pages_checked"]} pages.', 'success')
    with scan_lock:
        scan_state['running'] = False
        scan_state['done'] = True


def download_pdf(url):
    try:
        r = requests.get(url, headers=HEADERS, timeout=30, stream=True)
        r.raise_for_status()
        return r.content, r.headers.get('content-type', 'application/pdf')
    except Exception:
        return None, None


def get_frontend():
    frontend_path = os.path.join(os.path.dirname(__file__), 'index.html')
    with open(frontend_path, 'r') as f:
        return f.read()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        params = urllib.parse.parse_qs(parsed.query)

        if path in ('/', '/index.html'):
            body = get_frontend().encode()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', len(body))
            self.end_headers()
            self.wfile.write(body)

        elif path == '/status':
            with scan_lock:
                since = float(params.get('since', [0])[0])
                all_logs = list(scan_state['logs'])
                data = {
                    'running': scan_state['running'],
                    'done': scan_state['done'],
                    'pages_checked': scan_state['pages_checked'],
                    'pdf_count': len(scan_state['pdfs']),
                    'pdfs': scan_state['pdfs'],
                    'logs': [l for l in all_logs if l['t'] > since],
                }
            self.send_json(data)

        elif path == '/download':
            url = params.get('url', [''])[0]
            name = params.get('name', [''])[0]  # Use display name for download filename
            if not url:
                self.send_json({'error': 'No URL'}, 400)
                return
            content, ct = download_pdf(url)
            if not content:
                self.send_json({'error': 'Download failed'}, 500)
                return
            # Use the display name (with parent prefix) as the saved filename
            if not name:
                name = urllib.parse.unquote(url.split('/')[-1].split('?')[0])
            # Make sure it ends in .pdf
            if not name.lower().endswith('.pdf'):
                name += '.pdf'
            self.send_response(200)
            self.send_header('Content-Type', ct or 'application/pdf')
            self.send_header('Content-Disposition', f'attachment; filename="{name}"')
            self.send_header('Content-Length', len(content))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(content)

        elif path == '/stop':
            with scan_lock:
                scan_state['running'] = False
            self.send_json({'ok': True})

        elif path == '/zip':
            url_param = params.get('urls', [''])[0]
            name_param = params.get('names', [''])[0]
            if not url_param:
                self.send_json({'error': 'No URLs'}, 400)
                return
            urls = url_param.split('|')
            names = name_param.split('|') if name_param else urls
            def fetch_one(args):
                    u, n = args
                    content, _ = download_pdf(u)
                    return n, content

            with ThreadPoolExecutor(max_workers=8) as ex:
                results = list(ex.map(fetch_one, zip(urls, names)))

            buf = io.BytesIO()
            with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
                seen_names = {}
                for name, content in results:
                    if not content:
                        continue
                    if not name.lower().endswith('.pdf'):
                        name += '.pdf'
                    if name in seen_names:
                        seen_names[name] += 1
                        base, ext = name.rsplit('.', 1)
                        name = f"{base} ({seen_names[name]}).{ext}"
                    else:
                        seen_names[name] = 0
                    zf.writestr(name, content)
            zip_bytes = buf.getvalue()
            self.send_response(200)
            self.send_header('Content-Type', 'application/zip')
            self.send_header('Content-Disposition', 'attachment; filename="pdf_hunter.zip"')
            self.send_header('Content-Length', len(zip_bytes))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(zip_bytes)

        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/scan':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            url = body.get('url', '').strip()
            max_depth = int(body.get('depth', 2))
            same_domain = bool(body.get('same_domain', True))
            strict_path = bool(body.get('strict_path', True))
            name_filter = body.get('name_filter', '').strip()

            if not url:
                self.send_json({'error': 'No URL provided'}, 400)
                return
            if scan_state['running']:
                self.send_json({'error': 'Scan already running'}, 409)
                return

            t = threading.Thread(target=do_scan, args=(url, max_depth, same_domain, strict_path, name_filter), daemon=True)
            t.start()
            self.send_json({'ok': True})
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == '__main__':
    PORT = 7734
    server = ThreadingHTTPServer(('localhost', PORT), Handler)
    print(f"""
╔══════════════════════════════════════╗
║         PDF HUNTER - READY           ║
╠══════════════════════════════════════╣
║  Open: http://localhost:{PORT}       ║
║  Press Ctrl+C to stop                ║
╚══════════════════════════════════════╝
""")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
