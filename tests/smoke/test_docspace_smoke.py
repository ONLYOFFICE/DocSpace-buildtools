import hashlib
import json
import os
import time
import urllib.error
import urllib.request
import uuid

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import WebDriverException

SERVER_URL = os.environ.get('SERVER_URL', 'http://localhost').rstrip('/')
PORTAL_EMAIL = os.environ.get('PORTAL_EMAIL', 'smoke@example.com')
PORTAL_PASSWORD = os.environ.get('PORTAL_PASSWORD', 'Smoke-Test-2026')
LICENSE_CONTENT = os.environ.get('LICENSE')
LICENSE_FILE = os.environ.get('LICENSE_FILE')

# Values produced by earlier tests and consumed by later ones (tests run in file order)
state = {}

# Readiness by DOM state; isDocumentLoadComplete only when the build exports it (EE strips it)
LOAD_COMPLETE_JS = ("var api = window.editor || (window.Asc && window.Asc.editor);"
                    " var sdk = document.getElementById('editor_sdk');"
                    " return document.readyState === 'complete' && !!api"
                    " && !document.querySelector('.loadmask, .asc-loadmask')"
                    " && !!(sdk && sdk.children.length)"
                    " && (api.isDocumentLoadComplete === undefined"
                    "     || api.isDocumentLoadComplete === true)")

# ANSI color codes
GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
RESET = '\033[0m'

def step(message):
    """Open a one-line progress entry; close it with done()/skip()/fail()."""
    print(f"{BLUE}  → {message}{RESET} ... ", end='', flush=True)

def done(note='ok'):
    print(f"{GREEN}{note}{RESET}")

def skip(note):
    print(f"{YELLOW}{note}{RESET}")

def fail(note):
    print(f"{RED}{note}{RESET}")

@pytest.fixture(autouse=True)
def _start_progress_block():
    """Start test output on a fresh line after the pytest test id."""
    print(flush=True)
    yield

def api(path, method='GET', data=None, headers=None, raw_body=None, timeout=60):
    """Call the DocSpace REST API; returns (status, parsed json)."""
    all_headers = {'Content-Type': 'application/json', **(headers or {})}
    body = raw_body if raw_body is not None else (json.dumps(data).encode() if data else None)
    request = urllib.request.Request(SERVER_URL + '/api/2.0' + path, method=method, headers=all_headers, data=body)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b'{}')

def auth_headers():
    return {'Authorization': state['token']}

def make_driver():
    chrome_options = Options()
    chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')
    chrome_options.add_argument('--window-size=1920,1080')
    # capture the browser console so editor-load timeouts can show the actual JS error
    chrome_options.set_capability('goog:loggingPrefs', {'browser': 'ALL'})

    # Remote WebDriver (e.g. selenium/standalone-chromium container on ARM)
    remote_url = os.environ.get('SELENIUM_REMOTE_URL')
    if remote_url:
        return webdriver.Remote(command_executor=remote_url, options=chrome_options)

    # Optional explicit paths; runner images may export a stale CHROME_BIN, so verify it exists
    chrome_bin = os.environ.get('CHROME_BIN')
    if chrome_bin and os.path.isfile(chrome_bin):
        chrome_options.binary_location = chrome_bin

    chromedriver_path = os.environ.get('CHROMEDRIVER_PATH')
    service = Service(chromedriver_path) if chromedriver_path else None

    return webdriver.Chrome(service=service, options=chrome_options)

def multipart_body(field_name, filename, content):
    """Build a single-file multipart request body; returns (body, content type)."""
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="{field_name}"; filename="{filename}"\r\n'
            f'Content-Type: application/octet-stream\r\n\r\n').encode() \
           + content + f'\r\n--{boundary}--\r\n'.encode()
    return body, f'multipart/form-data; boundary={boundary}'

def wait_editor_loaded(driver, web_url):
    """Open an editor page with the auth cookie and wait until the document renders."""
    driver.get(SERVER_URL)
    driver.add_cookie({'name': 'asc_auth_key', 'value': state['token']})

    # a stuck editor never recovers on its own — short waits with page reloads beat one long wait
    editor_timeout = 30
    attempts = 3
    for attempt in range(1, attempts + 1):
        step(f"Editor: {web_url}" + (f" (attempt {attempt})" if attempt > 1 else ""))
        driver.get(web_url)
        WebDriverWait(driver, 60).until(EC.frame_to_be_available_and_switch_to_it((By.TAG_NAME, 'iframe')))
        done('iframe ok')

        step('Loading document in the editor')
        start = time.time()
        while time.time() - start < editor_timeout:
            try:
                if driver.execute_script(LOAD_COMPLETE_JS):
                    done(f"done in {time.time() - start:.1f}s")
                    return
            except WebDriverException:
                pass
            time.sleep(1)
        fail(f"not loaded within {editor_timeout}s" + (", reloading" if attempt < attempts else ""))
    print(driver.execute_script(
        "var api = window.editor || (window.Asc && window.Asc.editor);"
        " var sdk = document.getElementById('editor_sdk');"
        " return {readyState: document.readyState, hasApi: !!api,"
        " loadComplete: api ? api.isDocumentLoadComplete : null,"
        " loadmask: !!document.querySelector('.loadmask, .asc-loadmask'),"
        " sdkChildren: sdk ? sdk.children.length : null,"
        " iframes: document.getElementsByTagName('iframe').length,"
        " scripts: [].map.call(document.scripts, function(s){return s.src;}).filter(Boolean).slice(0, 5)}"))
    try:
        print('Browser console (last 30 entries):')
        for entry in driver.get_log('browser')[-30:]:
            print(f"  [{entry.get('level')}] {entry.get('message')}")
    except WebDriverException as log_error:
        print(f"Could not collect browser console: {log_error}")
    raise AssertionError(f"Editor did not load in {attempts} attempts of {editor_timeout}s")

def password_hash():
    hash_params = state['settings']['passwordHash']
    return hashlib.pbkdf2_hmac('sha256', PORTAL_PASSWORD.encode(), hash_params['salt'].encode(),
                               hash_params['iterations'], hash_params['size'] // 8).hex()

def test_settings():
    """The portal API must respond and identify itself as DocSpace."""
    step(f"GET {SERVER_URL}/api/2.0/settings")
    deadline = time.time() + 300
    status, body = None, {}
    while time.time() < deadline:
        try:
            status, body = api('/settings', timeout=10)
        except (urllib.error.URLError, OSError):
            status = None
        if status == 200:
            break
        print('.', end='', flush=True)
        time.sleep(10)
    assert status == 200, f"settings API failed: HTTP {status}"
    state['settings'] = body['response']
    assert state['settings'].get('docSpace'), 'portal does not identify itself as DocSpace'

    version = state['settings'].get('version') or ''
    expected_version = os.environ.get('EXPECTED_VERSION')
    version_matches = not expected_version or version == expected_version \
        or version.startswith(expected_version + '.')
    if not version_matches:
        fail(f"expected version {expected_version}, got {version}")
    assert version_matches, f"Expected version {expected_version}, got {version}"
    done(f"version {version}")

def test_wizard():
    """Complete the first-run wizard through the API (uploads a license when required)."""
    if 'wizardToken' not in state['settings']:
        step('Wizard')
        skip('skipped — already completed')
        pytest.skip('Wizard is already completed')
    confirm = {'confirm': state['settings']['wizardToken']}

    status, body = api('/settings/license/required', headers=confirm)
    if status == 200 and body.get('response'):
        step('Uploading license')
        license_bytes = LICENSE_CONTENT.encode() if LICENSE_CONTENT else None
        if not license_bytes and LICENSE_FILE and os.path.isfile(LICENSE_FILE):
            with open(LICENSE_FILE, 'rb') as license_file:
                license_bytes = license_file.read()
        assert license_bytes, 'License is required but neither LICENSE nor LICENSE_FILE is set'
        multipart, content_type = multipart_body('Files', 'license.lic', license_bytes)
        status, body = api('/settings/license', 'POST', raw_body=multipart,
                           headers={**confirm, 'Content-Type': content_type})
        assert status == 200, f"license upload failed: HTTP {status}, {json.dumps(body)[:200]}"
        done(str(body.get('response')))

    step('Completing wizard')
    status, body = api('/settings/wizard/complete', 'PUT',
                       {'email': PORTAL_EMAIL, 'PasswordHash': password_hash(), 'lng': 'en', 'timeZone': 'UTC'},
                       confirm)
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and body.get('response', {}).get('completed'), \
        f"wizard completion failed: HTTP {status}, {json.dumps(body)[:300]}"
    done('completed')

def test_auth():
    """The portal owner must be able to authenticate."""
    step(f"Authenticating as {PORTAL_EMAIL}")
    status, body = api('/authentication', 'POST', {'userName': PORTAL_EMAIL, 'passwordHash': password_hash()})
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and body.get('response', {}).get('token'), f"authentication failed: HTTP {status}"
    state['token'] = body['response']['token']
    done()

def test_create_document():
    """A new document must be created in My Documents."""
    step('Creating smoke.docx in My Documents')
    status, body = api('/files/@my/file', 'POST', {'title': 'smoke.docx'}, auth_headers())
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    created = body.get('response', {})
    assert status == 200 and created.get('id') and created.get('webUrl'), \
        f"file creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    state['file'] = created
    done(f"id {created['id']}")

def test_people_self():
    """The People module must return the authenticated owner profile."""
    step(f"GET {SERVER_URL}/api/2.0/people/@self")
    status, body = api('/people/@self', headers=auth_headers())
    profile = body.get('response', {})
    assert status == 200 and profile.get('email') == PORTAL_EMAIL, \
        f"people/@self failed: HTTP {status}, {json.dumps(body)[:200]}"
    done(profile.get('displayName') or profile['email'])

def test_create_room():
    """A custom room must be created — the core DocSpace collaboration entity."""
    step('Creating a custom room')
    status, body = api('/files/rooms', 'POST', {'title': 'smoke room', 'roomType': 5}, auth_headers())
    room = body.get('response', {})
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and room.get('id'), f"room creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"id {room['id']}")

def test_upload_download():
    """An uploaded file must come back byte-identical — storage round-trip."""
    content = b'DocSpace smoke upload check'

    step('Uploading smoke-upload.txt to My Documents')
    multipart, content_type = multipart_body('file', 'smoke-upload.txt', content)
    status, body = api('/files/@my/upload', 'POST', raw_body=multipart,
                       headers={**auth_headers(), 'Content-Type': content_type})
    uploaded = (body.get('response') or [{}])[0]
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and uploaded.get('viewUrl'), f"upload failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"id {uploaded.get('id')}")

    step('Downloading it back')
    request = urllib.request.Request(uploaded['viewUrl'], headers=auth_headers())
    with urllib.request.urlopen(request, timeout=60) as response:
        downloaded = response.read()
    assert downloaded == content, f"downloaded content differs: {downloaded[:60]!r}"
    done(f"{len(downloaded)} bytes, content matches")

def test_editor():
    """The created document must open and render in the editor."""
    driver = make_driver()
    try:
        wait_editor_loaded(driver, state['file']['webUrl'])
    finally:
        driver.quit()

@pytest.mark.parametrize('extension', ['xlsx', 'pptx'])
def test_editor_types(extension):
    """Spreadsheet and presentation editors must render too (different sdkjs builds)."""
    step(f"Creating smoke.{extension}")
    status, body = api('/files/@my/file', 'POST', {'title': f'smoke.{extension}'}, auth_headers())
    created = body.get('response', {})
    assert status == 200 and created.get('webUrl'), f"file creation failed: HTTP {status}"
    done(f"id {created['id']}")

    driver = make_driver()
    try:
        wait_editor_loaded(driver, created['webUrl'])
    finally:
        driver.quit()
