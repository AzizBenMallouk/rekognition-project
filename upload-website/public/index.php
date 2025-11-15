<?php
declare(strict_types=1);

/**
 * Minimal UI + API in one file.
 * - GET  /           -> renders HTML form
 * - POST /upload-url -> returns presigned PUT url (JSON)
 */

require __DIR__ . '/../vendor/autoload.php';

use Aws\S3\S3Client;

// --- tiny .env loader (same as before) ----------------------
$envFile = __DIR__ . '/../.env';
if (is_readable($envFile)) {
    foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') continue;
        if (!str_contains($line, '=')) continue;
        [$k, $v] = array_map('trim', explode('=', $line, 2));
        $_ENV[$k] = $v;
        putenv("$k=$v");
    }
}

function json_response(int $code, array $payload): void {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($payload);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path   = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
// ---------- API endpoint: POST /upload-url ----------
if ($method === 'POST' && $path === '/upload-url') {
    $raw = file_get_contents('php://input') ?: '';
    $data = json_decode($raw, true) ?: [];
    $name = trim($data['name'] ?? '');

    if ($name === '') {
        json_response(400, ['error' => 'name is required']);
    }

    $bucket	 = getenv('S3_BUCKET') ?: 'brief-s3-bucket';
    $region	 = getenv('AWS_REGION') ?: 'us-east-1';
    $contentType = getenv('UPLOAD_CONTENT_TYPE') ?: 'image/jpeg';

    if ($bucket === '') {
        json_response(500, ['error' => 'S3_BUCKET not configured']);
    }

    // build S3 client (uses instance profile)
    $s3 = new S3Client(['version' => '2006-03-01', 'region' => $region]);

    $slug = strtolower(preg_replace('/[^a-z0-9]+/', '-', $name));
    $rand = bin2hex(random_bytes(16));
    // NOTE: we fix ".jpg"; if you want to keep original extension, detect client-side and pass it to /upload-url
    $key  = "uploads/{$slug}/{$rand}.jpg";

    try {
	$cmd = $s3->getCommand('PutObject', [
            'Bucket'	  => $bucket,
            'Key'         => $key,
            'ContentType' => $contentType,
            // IMPORTANT: include metadata in the signature; client must send the same header
            'Metadata'    => ['name' => $name],
        ]);
        $req = $s3->createPresignedRequest($cmd, '+5 minutes');

        json_response(200, [
            'uploadUrl'   => (string)$req->getUri(),
            'bucket'	  => $bucket,
            'key'         => $key,
            'contentType' => $contentType,
            'metaHeader'  => 'x-amz-meta-name', // for the browser PUT
            'metaValue'   => $name
        ]);
    } catch (\Throwable $e) {
        json_response(500, ['error' => $e->getMessage()]);
    }
}

// ---------- UI (GET /) ----------
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>Face Upload</title>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <style>
    :root { --bg:#0f172a; --card:#111827; --text:#e5e7eb; --muted:#94a3b8; --accent:#22c55e; --danger:#ef4444; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, "Helvetica Neue", Arial; background: linear-gradient(135deg,#0f172a,#1f2937); color:var(--text);>
    .card { width:100%; max-width:560px; background:rgba(17,24,39,.8); border:1px solid rgba(148,163,184,.15); border-radius:16px; padding:24px; box-shadow: 0 10px 30px rgba(0,0,0,.35); }
    h1 { margin:0 0 4px; font-size:22px; }
    p { margin:0 0 18px; color:var(--muted); }
    label { display:block; font-size:14px; margin:14px 0 6px; color:#cbd5e1; }
    input[type="text"], input[type="file"] {
      width:100%; padding:12px 14px; border-radius:12px; border:1px solid rgba(148,163,184,.25); background:#0b1220; color:var(--text);
      outline:none;
    }
    input[type="text"]:focus, input[type="file"]:focus { border-color:#60a5fa; box-shadow: 0 0 0 3px rgba(96,165,250,.2); }
    .row { display:flex; gap:12px; align-items:center; }
    .btn {
      display:inline-flex; align-items:center; justify-content:center;
      gap:8px; padding:12px 16px; border-radius:12px; border:1px solid rgba(148,163,184,.2);
      background:linear-gradient(180deg,#22c55e,#16a34a); color:#052e16; font-weight:700; cursor:pointer;
      transition: transform .05s ease;
    }
    .btn:hover { filter:brightness(1.03); }
    .btn:active { transform: translateY(1px); }
    .hint { font-size:12px; color:#9ca3af; margin-top:8px; }
    .out { margin-top:16px; padding:12px; border-radius:10px; background:#0b1220; border:1px solid rgba(148,163,184,.2); min-height:44px; white-space:pre-wrap; }
    .ok { color: var(--accent); }
    .err { color: var(--danger); }
    .preview { margin-top:10px; display:none; }
    .preview img { max-width:100%; border-radius:12px; border:1px solid rgba(148,163,184,.2); }
  </style>
</head>
<body>
  <div class="card">
    <h1>Upload face (Without IA)</h1>
    <p>Enter a name and choose a photo. The file uploads directly to S3 with a pre-signed URL.</p>

    <form id="uploadForm">
      <label for="name">Name</label>
      <input id="name" name="name" type="text" placeholder="e.g. John Doe" required autocomplete="off"/>

      <label for="file">Photo (JPEG)</label>
      <input id="file" name="file" type="file" accept="image/jpeg,image/jpg" required />

      <div class="row" style="margin-top:16px;">
        <button class="btn" type="submit">
          <span>Upload</span>
        </button>
        <span id="status" class="hint">Ready</span>
      </div>

      <div class="preview" id="preview">
        <img id="previewImg" alt="preview"/>
      </div>
      <div class="out" id="output"></div>
    </form>
  </div>

<script>
const form = document.getElementById('uploadForm');
const statusEl = document.getElementById('status');
const out = document.getElementById('output');
const fileInput = document.getElementById('file');
const nameInput = document.getElementById('name');
const preview = document.getElementById('preview');
const previewImg = document.getElementById('previewImg');

fileInput.addEventListener('change', () => {
  const f = fileInput.files?.[0];
  if (!f) { preview.style.display = 'none'; return; }
  const url = URL.createObjectURL(f);
  previewImg.src = url;
  preview.style.display = 'block';
});

function setStatus(text, cls='') {
  statusEl.textContent = text;
  statusEl.className = 'hint ' + cls;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  out.textContent = '';
  setStatus('Requesting upload URL…');

  const file = fileInput.files?.[0];
  const name = nameInput.value.trim();
  if (!file) return setStatus('No file selected', 'err');
  if (!name) return setStatus('Name is required', 'err');
  // 1) ask server for a pre-signed URL
  let resp;
  try {
    resp = await fetch('/upload-url', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ name })
    });
  } catch (err) {
    setStatus('Network error contacting server', 'err');
    return;
  }
  if (!resp.ok) {
    setStatus('Server error creating URL', 'err');
    const txt = await resp.text().catch(()=> '');
    out.textContent = txt;
    return;
  }

  const { uploadUrl, key, contentType, metaHeader, metaValue } = await resp.json();

  // 2) PUT to S3 with same headers that were signed
  setStatus('Uploading to S3…');
  try {
    const put = await fetch(uploadUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': contentType,
        // IMPORTANT: must match the metadata used during signing
        [metaHeader || 'x-amz-meta-name']: metaValue || name
      },
      body: file
    });
    if (!put.ok) {
      const t = await put.text().catch(()=> '');
      throw new Error('S3 upload failed: ' + put.status + ' ' + t);
    }
  } catch (err) {
    setStatus('Upload failed', 'err');
    out.textContent = String(err);
    return;
  }

  setStatus('Uploaded successfully', 'ok');
  out.innerHTML = `
✅ Uploaded!<br>
<strong>S3 Key:</strong> ${key}<br>
Your backend Lambda will process it shortly.`;
});
</script>
</body>
</html>
