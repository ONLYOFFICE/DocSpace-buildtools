import base64
import hashlib
import io
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile

import pytest
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.action_chains import ActionChains
from selenium.common.exceptions import WebDriverException

SERVER_URL = os.environ.get('SERVER_URL', 'http://localhost').rstrip('/')
PORTAL_EMAIL = os.environ.get('PORTAL_EMAIL', 'smoke@example.com')
PORTAL_PASSWORD = os.environ.get('PORTAL_PASSWORD', 'Smoke-Test-2026')
LICENSE_CONTENT = os.environ.get('LICENSE')
LICENSE_FILE = os.environ.get('LICENSE_FILE')
AMI_ID = os.environ.get('AMI_ID')
# standalone, stack or microservices; unset for package installs
DEPLOYMENT_MODE = os.environ.get('DEPLOYMENT_MODE', '')
# JSON file shared between separate pytest runs (seed before a restart or update, verify after)
STATE_FILE = os.environ.get('SMOKE_STATE_FILE')
DASHBOARDS_USERNAME = os.environ.get('DASHBOARDS_USERNAME')
DASHBOARDS_PASSWORD = os.environ.get('DASHBOARDS_PASSWORD')
# the restore regenerates user IDs and invalidates every password, so it runs as the last step on its own
RUN_RESTORE = os.environ.get('SMOKE_RUN_RESTORE') == 'true'

# tests of the Docker deployments only; package installs run this file without DEPLOYMENT_MODE
docker_only = pytest.mark.skipif(not DEPLOYMENT_MODE, reason='runs on Docker deployments only')

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

# asc_isDocumentModified is not exported in EE builds — degrade to a no-op there
NOT_MODIFIED_JS = ("var api = window.editor || (window.Asc && window.Asc.editor);"
                   " return api && api.asc_isDocumentModified"
                   " ? !api.asc_isDocumentModified() : true")

TEST_TEXT = "Test text for editor verification"

SELECTED_TEXT_JS = ("var api = window.editor || (window.Asc && window.Asc.editor);"
                    " return api && api.asc_GetSelectedText ? api.asc_GetSelectedText() : null")

# FileShare value of the files API
READ_ACCESS = 2

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
    """Call the ONLYOFFICE Apps REST API; returns (status, parsed json)."""
    all_headers = {'Content-Type': 'application/json', **(headers or {})}
    body = raw_body if raw_body is not None else (json.dumps(data).encode() if data else None)
    request = urllib.request.Request(SERVER_URL + '/api/2.0' + path, method=method, headers=all_headers, data=body)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        try:
            return error.code, json.loads(error.read() or b'{}')
        except json.JSONDecodeError:
            # nginx serves its own HTML error page while an upstream is still starting
            return error.code, {}

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

def dismiss_dialogs(driver):
    """Close modal dialogs that may cover the editor (e.g. notices on first open)."""
    for _ in range(5):
        buttons = [b for b in driver.find_elements(By.CSS_SELECTOR, "button.dlg-btn[result='ok']")
                   if b.is_displayed()]
        if not buttons:
            return
        # dialogs may stack — the last one is on top and intercepts clicks
        button = buttons[-1]
        text = driver.execute_script(
            "var w = arguments[0].closest('.asc-window'); return w ? w.innerText : '';", button)
        step(f"Dismissing dialog: {' '.join(text.split())[:120]!r}")
        driver.execute_script("arguments[0].click();", button)
        time.sleep(1)
        done('closed')

def dump_page_state(driver):
    """Print debug info that explains a stuck or missing editor."""
    print(f"Current URL: {driver.current_url}")
    try:
        page_state = driver.execute_script(
            "var api = window.editor || (window.Asc && window.Asc.editor);"
            " var sdk = document.getElementById('editor_sdk');"
            " return {readyState: document.readyState, hasApi: !!api,"
            " loadComplete: api ? api.isDocumentLoadComplete : null,"
            " loadmask: !!document.querySelector('.loadmask, .asc-loadmask'),"
            " sdkChildren: sdk ? sdk.children.length : null,"
            " iframes: document.getElementsByTagName('iframe').length,"
            " scripts: [].map.call(document.scripts, function(s){return s.src;}).filter(Boolean).slice(0, 5)}")
        print(f"Page state: {page_state}")
    except WebDriverException as script_error:
        print(f"Could not collect page state: {script_error}")
    try:
        print('Browser console (last 30 entries):')
        for entry in driver.get_log('browser')[-30:]:
            print(f"  [{entry.get('level')}] {entry.get('message')}")
    except (AttributeError, WebDriverException) as log_error:
        print(f"Could not collect browser console: {log_error}")
    print('Current page source:')
    print(driver.page_source[:1000])

def wait_for_js(driver, script, timeout, description):
    """Poll a JS condition inside the current frame until it returns true."""
    step(description)
    start = time.time()
    while time.time() - start < timeout:
        try:
            if driver.execute_script(script):
                done(f"done in {time.time() - start:.1f}s")
                return
        except WebDriverException:
            pass
        time.sleep(1)
    fail(f"timeout after {timeout}s")
    raise AssertionError(f"Timed out waiting for {description}")

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
    dump_page_state(driver)
    raise AssertionError(f"Editor did not load in {attempts} attempts of {editor_timeout}s")

def password_hash():
    hash_params = state['settings']['passwordHash']
    return hashlib.pbkdf2_hmac('sha256', PORTAL_PASSWORD.encode(), hash_params['salt'].encode(),
                               hash_params['iterations'], hash_params['size'] // 8).hex()

def authenticate():
    """Log in as the portal owner and keep the token for later API calls."""
    status, body = api('/authentication', 'POST', {'userName': PORTAL_EMAIL, 'passwordHash': password_hash()})
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and body.get('response', {}).get('token'), f"authentication failed: HTTP {status}"
    state['token'] = body['response']['token']

def http_request(url, headers=None, timeout=60, method='GET'):
    """Fetch any URL; returns (status, body bytes) and does not raise on HTTP errors."""
    request = urllib.request.Request(url, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

def download(url, headers=None):
    status, content = http_request(url, headers)
    assert status == 200, f"download failed: HTTP {status} for {url}"
    return content

def payload(body):
    """Portal endpoints wrap results into 'response'; the identity service answers bare."""
    return body['response'] if isinstance(body, dict) and 'response' in body else body

def find_key(node, key):
    """Depth-first search for a non-empty key in nested JSON; None when absent."""
    if isinstance(node, dict):
        if node.get(key):
            return node[key]
        children = node.values()
    elif isinstance(node, list):
        children = node
    else:
        return None
    for child in children:
        found = find_key(child, key)
        if found:
            return found
    return None

def poll_until(check, timeout, description, interval=3):
    """Call check() until it returns a truthy value, which is then returned."""
    step(description)
    start = time.time()
    while time.time() - start < timeout:
        try:
            result = check()
        except (urllib.error.URLError, OSError, json.JSONDecodeError):
            # the portal may be briefly unreachable while a service restarts
            result = None
        if result:
            done(f"done in {time.time() - start:.1f}s")
            return result
        time.sleep(interval)
    fail(f"timeout after {timeout}s")
    raise AssertionError(f"Timed out waiting for {description}")

def skip_test(reason):
    skip(reason)
    pytest.skip(reason)

def my_folder_id():
    """Numeric ID of My Documents of the portal owner."""
    if 'my_folder' not in state:
        status, body = api('/files/@my', headers=auth_headers())
        folder_id = body.get('response', {}).get('current', {}).get('id')
        assert status == 200 and folder_id, f"could not read My Documents: HTTP {status}, {json.dumps(body)[:200]}"
        state['my_folder'] = folder_id
    return state['my_folder']

def create_document(title):
    status, body = api('/files/@my/file', 'POST', {'title': title}, auth_headers())
    created = body.get('response', {})
    assert status == 200 and created.get('id') and created.get('webUrl'), \
        f"creation of {title} failed: HTTP {status}, {json.dumps(body)[:300]}"
    return created

def upload_file(title, content):
    multipart, content_type = multipart_body('file', title, content)
    status, body = api('/files/@my/upload', 'POST', raw_body=multipart,
                       headers={**auth_headers(), 'Content-Type': content_type})
    uploaded = (body.get('response') or [{}])[0]
    assert status == 200 and uploaded.get('id'), f"upload of {title} failed: HTTP {status}, {json.dumps(body)[:300]}"
    return uploaded

def download_file(file_id):
    status, body = api(f"/files/file/{file_id}", headers=auth_headers())
    view_url = body.get('response', {}).get('viewUrl')
    assert status == 200 and view_url, f"could not fetch file info: HTTP {status}, {json.dumps(body)[:200]}"
    return download(view_url, auth_headers())

def create_share_key(file_id, access):
    """Create the primary external link of a file and return its request token."""
    status, body = api(f"/files/file/{file_id}/link", 'POST', {'access': access}, auth_headers())
    assert status == 200, f"link creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    shared = payload(body)
    key = find_key(shared, 'requestToken')
    if not key:
        link = find_key(shared, 'shareLink') or ''
        key = (urllib.parse.parse_qs(urllib.parse.urlparse(link).query).get('share') or [None])[0]
    assert key, f"no share key in the link response: {json.dumps(body)[:300]}"
    return key

def focus_editor(driver):
    WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.ID, 'editor_sdk'))).click()

def make_docx(text):
    """Build a minimal DOCX with one paragraph."""
    namespace = 'http://schemas.openxmlformats.org/'
    parts = {
        '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                               f'<Types xmlns="{namespace}package/2006/content-types">'
                               '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                               '<Default Extension="xml" ContentType="application/xml"/>'
                               '<Override PartName="/word/document.xml" '
                               'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
                               '</Types>',
        '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                       f'<Relationships xmlns="{namespace}package/2006/relationships">'
                       f'<Relationship Id="rId1" Type="{namespace}officeDocument/2006/relationships/officeDocument" '
                       'Target="word/document.xml"/></Relationships>',
        'word/document.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                             f'<w:document xmlns:w="{namespace}wordprocessingml/2006/main"><w:body>'
                             f'<w:p><w:r><w:t>{text}</w:t></w:r></w:p></w:body></w:document>',
    }
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, content in parts.items():
            archive.writestr(name, content)
    return buffer.getvalue()

def selected_text(driver):
    """Select everything in the editor, read it and move the caret to the end again."""
    focus_editor(driver)
    ActionChains(driver).key_down(Keys.CONTROL).send_keys('a').key_up(Keys.CONTROL).perform()
    time.sleep(1)
    text = driver.execute_script(SELECTED_TEXT_JS)
    ActionChains(driver).key_down(Keys.CONTROL).send_keys(Keys.END).key_up(Keys.CONTROL).perform()
    return text or ''

def type_in_editor(driver, text, attempts=3):
    """Type at the end of the document, again while the editor swallows the keys; returns the document text."""
    content = ''
    for _ in range(attempts):
        focus_editor(driver)
        ActionChains(driver).key_down(Keys.CONTROL).send_keys(Keys.END).key_up(Keys.CONTROL).perform()
        ActionChains(driver).send_keys(text).perform()
        time.sleep(2)
        content = selected_text(driver)
        # the editor capitalizes the first letter of a sentence
        if text.lower() in content.lower():
            break
    return content

@pytest.mark.bootstrap
def test_settings():
    """The portal API must respond and identify itself as Apps."""
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
    assert state['settings'].get('docSpace'), 'portal does not identify itself as Apps'

    version = state['settings'].get('version') or ''
    expected_version = os.environ.get('EXPECTED_VERSION')
    version_matches = not expected_version or version == expected_version \
        or version.startswith(expected_version + '.')
    if not version_matches:
        fail(f"expected version {expected_version}, got {version}")
    assert version_matches, f"Expected version {expected_version}, got {version}"
    done(f"version {version}")

@pytest.mark.bootstrap
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

    step('Completing wizard' + (f" (amiId={AMI_ID})" if AMI_ID else ''))
    wizard_body = {'email': PORTAL_EMAIL, 'PasswordHash': password_hash(), 'lng': 'en', 'timeZone': 'UTC'}
    if AMI_ID:
        wizard_body['amiId'] = AMI_ID
    status, body = api('/settings/wizard/complete', 'PUT', wizard_body, confirm)
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and body.get('response', {}).get('completed'), \
        f"wizard completion failed: HTTP {status}, {json.dumps(body)[:300]}"
    done('completed')

@pytest.mark.bootstrap
def test_auth():
    """The portal owner must be able to authenticate."""
    step(f"Authenticating as {PORTAL_EMAIL}")
    authenticate()
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
    """A custom room must be created — the core ONLYOFFICE Apps collaboration entity."""
    step('Creating a custom room')
    status, body = api('/files/rooms', 'POST', {'title': 'smoke room', 'roomType': 5}, auth_headers())
    room = body.get('response', {})
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and room.get('id'), f"room creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"id {room['id']}")

def test_upload_download():
    """An uploaded file must come back byte-identical — storage round-trip."""
    content = b'ONLYOFFICE Apps smoke upload check'

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

@pytest.mark.seed
def test_seed_persistent_data():
    """Create a room and a file that must survive restarts and updates."""
    marker = uuid.uuid4().hex
    room_title = f"persist {marker[:8]}"
    content = f"persistent content {marker}"

    step('Creating a room to verify after a restart or update')
    status, body = api('/files/rooms', 'POST', {'title': room_title, 'roomType': 5}, auth_headers())
    room = body.get('response', {})
    assert status == 200 and room.get('id'), f"room creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"id {room['id']}")

    step('Uploading persist.txt')
    uploaded = upload_file('persist.txt', content.encode())
    done(f"id {uploaded['id']}")

    state['seed'] = {'room_id': room['id'], 'room_title': room_title,
                     'file_id': uploaded['id'], 'file_content': content}
    if STATE_FILE:
        with open(STATE_FILE, 'w', encoding='utf-8') as state_file:
            json.dump(state['seed'], state_file)

@pytest.mark.verify
def test_verify_persistent_data():
    """The room and the file created before a restart or update must be intact."""
    step('Reading the persisted state')
    if 'seed' in state:
        skip_test('seeded in this run — verified by the next run')
    if not STATE_FILE or not os.path.isfile(STATE_FILE):
        skip_test('no persisted state file')
    with open(STATE_FILE, encoding='utf-8') as state_file:
        seed = json.load(state_file)
    done(f"room {seed['room_id']}, file {seed['file_id']}")

    step('Opening the persisted room')
    status, body = api(f"/files/{seed['room_id']}", headers=auth_headers())
    title = body.get('response', {}).get('current', {}).get('title')
    assert status == 200 and title == seed['room_title'], \
        f"room is gone or renamed: HTTP {status}, title {title!r}, {json.dumps(body)[:200]}"
    done(title)

    step('Downloading the persisted file')
    downloaded = download_file(seed['file_id'])
    assert downloaded.decode() == seed['file_content'], f"persisted content differs: {downloaded[:60]!r}"
    done('content matches')

def test_editor():
    """The created document must open, accept edits, save, and the save must persist."""
    driver = make_driver()
    try:
        wait_editor_loaded(driver, state['file']['webUrl'])
        dismiss_dialogs(driver)

        step('Typing test text')
        type_in_editor(driver, TEST_TEXT)
        done()

        step('Verifying the text reached the document')
        ActionChains(driver).key_down(Keys.CONTROL).send_keys('a').key_up(Keys.CONTROL).perform()
        time.sleep(1)
        selected = driver.execute_script(SELECTED_TEXT_JS)
        if not (selected and TEST_TEXT in selected):
            fail(f"not found (selection: {selected!r})")
        assert selected and TEST_TEXT in selected, \
            f"Typed text not found in the document (selection: {selected!r})"
        done('found')

        ActionChains(driver).key_down(Keys.CONTROL).send_keys('s').key_up(Keys.CONTROL).perform()
        wait_for_js(driver, NOT_MODIFIED_JS, 30, 'Saving document (Ctrl+S)')

        step('Downloading the saved file back')
        status, body = api(f"/files/file/{state['file']['id']}", headers=auth_headers())
        view_url = body.get('response', {}).get('viewUrl')
        assert status == 200 and view_url, f"could not fetch file info: HTTP {status}, {json.dumps(body)[:200]}"
        request = urllib.request.Request(view_url, headers=auth_headers())
        with urllib.request.urlopen(request, timeout=60) as response:
            downloaded = response.read()
        if not downloaded.startswith(b'PK'):
            fail(f"unexpected signature: {downloaded[:4]!r}")
        assert downloaded.startswith(b'PK'), f"Downloaded file is not a valid OOXML file (starts with {downloaded[:4]!r})"
        done(f"{len(downloaded)} bytes")
    except Exception as error:
        print(flush=True)
        fail(f"Test failed: {error}")
        dump_page_state(driver)
        raise
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
        dismiss_dialogs(driver)
    except Exception as error:
        print(flush=True)
        fail(f"{extension} editor failed: {error}")
        dump_page_state(driver)
        raise
    finally:
        driver.quit()

RTF_CONTENT = rb'{\rtf1\ansi\deff0{\fonttbl{\f0 Arial;}}\f0 Smoke conversion text\par}'

@docker_only
@pytest.mark.parametrize('source_title, target_title, signature', [
    ('smoke-convert.docx', 'smoke-converted.pdf', b'%PDF'),
    ('smoke-convert.rtf', 'smoke-converted.docx', b'PK'),
])
def test_conversion(source_title, target_title, signature):
    """Document Server must convert files: DOCX to PDF and legacy RTF to DOCX."""
    source = upload_file(source_title, RTF_CONTENT) if source_title.endswith('.rtf') else create_document(source_title)

    step(f"Converting {source_title} to {target_title}")
    status, body = api(f"/files/file/{source['id']}/copyas", 'POST',
                       {'destFolderId': my_folder_id(), 'destTitle': target_title}, auth_headers(), timeout=180)
    converted = body.get('response', {})
    if status != 200:
        fail(f"HTTP {status}: {json.dumps(body)[:200]}")
    assert status == 200 and converted.get('id'), f"conversion failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"id {converted['id']}")

    step('Checking the converted content')
    content = download_file(converted['id'])
    assert content.startswith(signature), f"{target_title} has an unexpected signature: {content[:8]!r}"
    done(f"{len(content)} bytes")

@docker_only
def test_file_versions():
    """Uploading over a file must keep both versions, each with its own content."""
    first = f"version one {uuid.uuid4().hex}".encode()
    second = f"version two {uuid.uuid4().hex}".encode()

    step('Uploading smoke-versions.txt')
    uploaded = upload_file('smoke-versions.txt', first)
    done(f"id {uploaded['id']}")

    step('Saving a second version')
    multipart, content_type = multipart_body('file', 'smoke-versions.txt', second)
    status, body = api(f"/files/{uploaded['id']}/update", 'PUT', raw_body=multipart,
                       headers={**auth_headers(), 'Content-Type': content_type})
    assert status == 200, f"version upload failed: HTTP {status}, {json.dumps(body)[:300]}"
    done()

    step('Reading the version history')
    status, body = api(f"/files/file/{uploaded['id']}/history", headers=auth_headers())
    versions = sorted(body.get('response') or [], key=lambda item: item.get('version', 0), reverse=True)
    assert status == 200 and len(versions) >= 2, f"expected two versions: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"{len(versions)} versions")

    step('Comparing the content of the newest and the oldest version')
    newest = download(f"{versions[0]['viewUrl']}&version={versions[0]['version']}", auth_headers())
    oldest = download(f"{versions[-1]['viewUrl']}&version={versions[-1]['version']}", auth_headers())
    assert newest == second, f"newest version differs: {newest[:60]!r}"
    assert oldest == first, f"oldest version differs: {oldest[:60]!r}"
    done('both match')

@docker_only
def test_fulltext_search():
    """OpenSearch must index uploaded documents: a word found only in the body must be searchable."""
    word = f"smokeneedle{uuid.uuid4().hex[:12]}"

    step('Uploading smoke-search.docx')
    uploaded = upload_file('smoke-search.docx', make_docx(f"Full text search check {word}"))
    done(f"id {uploaded['id']}")

    def found():
        status, body = api(f"/files/@my?filterValue={word}", headers=auth_headers())
        files = payload(body).get('files', []) if status == 200 else []
        return any(item.get('id') == uploaded['id'] for item in files)

    poll_until(found, 180, f"Searching for {word} in file content")

@docker_only
def test_public_link():
    """An external read link must open the file without a login, and only with its key."""
    document = create_document('smoke-link.docx')

    step('Creating the external link')
    key = create_share_key(document['id'], READ_ACCESS)
    done('created')

    step('Opening the file anonymously with the link key')
    status, body = api(f"/files/file/{document['id']}", headers={'Request-Token': key})
    assert status == 200 and payload(body).get('id') == document['id'], \
        f"anonymous access with the key failed: HTTP {status}, {json.dumps(body)[:200]}"
    done('opened')

    step('Opening the file anonymously without the key')
    status, _ = api(f"/files/file/{document['id']}")
    assert status in (401, 403, 404), f"file is open without the link key: HTTP {status}"
    done(f"refused with HTTP {status}")

@docker_only
def test_coediting():
    """Two sessions in one document must see each other's edits (Document Server, Redis, sockets)."""
    first_text = f"first-{uuid.uuid4().hex[:8]}"
    second_text = f"second-{uuid.uuid4().hex[:8]}"
    document = create_document('smoke-coedit.docx')

    seen = {}

    def sees(name, driver, expected):
        def check():
            seen[name] = selected_text(driver)
            # the editor capitalizes the first letter of a sentence
            return expected.lower() in seen[name].lower()
        return check

    first = make_driver()
    second = make_driver()
    try:
        wait_editor_loaded(first, document['webUrl'])
        dismiss_dialogs(first)
        step('First session types a line')
        typed = type_in_editor(first, first_text)
        assert first_text.lower() in typed.lower(), f"the typed line is not in the first session: {typed!r}"
        # a save would start a new document session; let the changes reach Document Server instead
        time.sleep(5)
        done(first_text)

        wait_editor_loaded(second, document['webUrl'])
        dismiss_dialogs(second)
        poll_until(sees('second', second, first_text), 60, 'Second session sees the first line', interval=2)

        step('Second session types a line')
        type_in_editor(second, second_text)
        done(second_text)
        poll_until(sees('first', first, second_text), 60, 'First session sees the second line', interval=2)
    except Exception as error:
        print(flush=True)
        fail(f"Co-editing failed: {error}")
        print(f"Last text read from each session: {seen}")
        for name, driver in (('first', first), ('second', second)):
            print(f"--- {name} session ---")
            dump_page_state(driver)
        raise
    finally:
        first.quit()
        second.quit()

@docker_only
def test_oauth_clients():
    """The identity service must list scopes, register a client, serve its public info and delete it."""
    step('Getting the identity signature')
    status, body = api('/security/oauth2/token', headers=auth_headers())
    signature = payload(body)
    assert status == 200 and isinstance(signature, str) and signature, \
        f"no identity signature: HTTP {status}, {json.dumps(body)[:200]}"
    headers = {'x-signature': signature, 'Cookie': f"x-signature={signature}"}
    done('received')

    step('Listing OAuth scopes')
    status, body = api('/oauth2/scopes', headers=headers)
    names = {item.get('name') for item in payload(body)} if status == 200 and isinstance(payload(body), list) else set()
    assert 'openid' in names, f"scopes are missing: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"{len(names)} scopes")

    step('Registering an OAuth client')
    client_request = {
        'name': f"Smoke client {uuid.uuid4().hex[:8]}",
        'description': 'Created by the smoke test',
        'logo': 'data:image/png;base64,ivBORw0KGgo=',
        'allow_pkce': False,
        'is_public': False,
        'website_url': 'https://example.com',
        'terms_url': 'https://example.com/terms',
        'policy_url': 'https://example.com/policy',
        'redirect_uris': ['https://example.com/callback'],
        'allowed_origins': ['https://example.com'],
        'logout_redirect_uri': 'https://example.com/logout',
        'scopes': ['openid', 'files:read'],
    }
    status, body = api('/oauth2/clients', 'POST', client_request, headers)
    client_id = find_key(body, 'client_id')
    assert status in (200, 201) and client_id, f"client creation failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(client_id)

    try:
        step('Reading the public info of the client without a login')
        status, body = api(f"/oauth2/clients/{client_id}/public/info")
        assert status == 200 and client_id in json.dumps(body), \
            f"public client info failed: HTTP {status}, {json.dumps(body)[:300]}"
        done('ok')
    finally:
        delete_status, _ = http_request(f"{SERVER_URL}/api/2.0/oauth2/clients/{client_id}", headers, method='DELETE')

    step('Deleting the client')
    assert delete_status in (200, 204), f"client deletion failed: HTTP {delete_status}"
    done(f"HTTP {delete_status}")

def test_dashboards():
    """OpenSearch Dashboards must sit behind basic auth and answer with the right credentials."""
    step('Dashboards')
    if DEPLOYMENT_MODE not in ('stack', 'microservices') or not DASHBOARDS_PASSWORD:
        skip_test('not deployed in this mode or no credentials given')
    done('deployed')

    step('Opening Dashboards without credentials')
    status, _ = http_request(f"{SERVER_URL}/dashboards/")
    assert status == 401, f"Dashboards are open without credentials: HTTP {status}"
    done('refused with HTTP 401')

    step('Reading the Dashboards status with credentials')
    credentials = base64.b64encode(f"{DASHBOARDS_USERNAME}:{DASHBOARDS_PASSWORD}".encode()).decode()
    status, content = http_request(f"{SERVER_URL}/dashboards/api/status", {'Authorization': f"Basic {credentials}"})
    assert status == 200, f"Dashboards status failed: HTTP {status}, {content[:200]!r}"
    done('HTTP 200')

def test_healthchecks():
    """The health checks service must answer through the proxy."""
    step('Health checks')
    if DEPLOYMENT_MODE != 'microservices':
        skip_test('the service is deployed in microservices mode only')
    done('deployed')

    step(f"GET {SERVER_URL}/healthchecks/liveness/")
    status, content = http_request(f"{SERVER_URL}/healthchecks/liveness/")
    assert status == 200, f"health checks liveness failed: HTTP {status}, {content[:200]!r}"
    done('HTTP 200')

@docker_only
@pytest.mark.restore
def test_backup_restore():
    """A portal backup must restore. Users get new IDs, so nobody can log in afterwards: no data checks here."""
    step('Backup and restore')
    if not RUN_RESTORE:
        skip_test('runs only with SMOKE_RUN_RESTORE=true, as the last step')
    done('enabled')

    step('Starting the backup into My Documents')
    status, body = api('/backup/startbackup', 'POST',
                       {'storageType': 'Documents', 'storageParams': [{'key': 'folderId', 'value': str(my_folder_id())}]},
                       auth_headers())
    backup_id = body.get('response', {}).get('taskId')
    assert status == 200 and backup_id, f"backup start failed: HTTP {status}, {json.dumps(body)[:300]}"
    done(f"task {backup_id}")

    def backup_finished():
        _, progress_body = api('/backup/getbackupprogress', headers=auth_headers())
        progress = progress_body.get('response')
        if progress:
            assert not progress.get('error'), f"backup failed: {progress.get('error')}"
            return progress.get('isCompleted')
        # a finished job may already be dropped from the queue — then the history has the record
        _, history_body = api('/backup/getbackuphistory', headers=auth_headers())
        return any(record.get('id') == backup_id for record in history_body.get('response') or [])

    poll_until(backup_finished, 600, 'Waiting for the backup to complete', interval=5)

    step('Starting the restore')
    status, body = api('/backup/startrestore', 'POST',
                       {'backupId': backup_id, 'storageType': 'Documents', 'notify': False}, auth_headers())
    assert status == 200, f"restore start failed: HTTP {status}, {json.dumps(body)[:300]}"
    done()

    def restore_finished():
        status, progress_body = api('/backup/getrestoreprogress')
        progress = progress_body.get('response') if status == 200 else None
        if not progress:
            return False
        assert not progress.get('error'), f"restore failed: {progress.get('error')}"
        return progress.get('isCompleted')

    poll_until(restore_finished, 900, 'Waiting for the restore to complete', interval=5)

    step('Checking that the restored portal answers')
    status, body = api('/settings', timeout=30)
    settings = body.get('response', {})
    assert status == 200 and settings.get('docSpace'), f"the portal does not answer after the restore: HTTP {status}"
    assert 'wizardToken' not in settings, 'the restored portal asks for the first-run wizard'
    done('settings answer, no wizard')
