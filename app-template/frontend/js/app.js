const API = '/api';
let token = localStorage.getItem('token');

const $ = (id) => document.getElementById(id);

function applyAuthState() {
  const loggedIn = !!token;
  $('btn-logout').classList.toggle('hidden', !loggedIn);
  $('btn-show-login').classList.toggle('hidden', loggedIn);
  $('btn-show-register').classList.toggle('hidden', loggedIn);
}

async function apiPost(path, body) {
  const res = await fetch(API + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { ok: res.ok, data: await res.json() };
}

async function checkHealth() {
  try {
    const res = await fetch(API + '/health');
    const data = await res.json();
    $('status-db').textContent = `API: ${data.status} — DB: ${data.db}`;
  } catch {
    $('status-db').textContent = 'API inaccessible';
  }
}

function showMsg(id, text, isError) {
  const el = $(id);
  el.textContent = text;
  el.className = 'msg ' + (isError ? 'error' : 'success');
}

$('btn-show-login').addEventListener('click', () => {
  $('section-login').classList.remove('hidden');
  $('section-register').classList.add('hidden');
});

$('btn-show-register').addEventListener('click', () => {
  $('section-register').classList.remove('hidden');
  $('section-login').classList.add('hidden');
});

$('btn-logout').addEventListener('click', () => {
  token = null;
  localStorage.removeItem('token');
  applyAuthState();
});

$('form-login').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const { ok, data } = await apiPost('/auth/login', {
    email: fd.get('email'),
    password: fd.get('password'),
  });
  if (ok) {
    token = data.token;
    localStorage.setItem('token', token);
    applyAuthState();
    $('section-login').classList.add('hidden');
    showMsg('msg-login', '', false);
  } else {
    showMsg('msg-login', data.error || 'Erreur de connexion', true);
  }
});

$('form-register').addEventListener('submit', async (e) => {
  e.preventDefault();
  const fd = new FormData(e.target);
  const { ok, data } = await apiPost('/auth/register', {
    email: fd.get('email'),
    password: fd.get('password'),
  });
  if (ok) {
    token = data.token;
    localStorage.setItem('token', token);
    applyAuthState();
    $('section-register').classList.add('hidden');
    showMsg('msg-register', 'Compte créé avec succès', false);
  } else {
    const msg = data.errors ? data.errors.join(', ') : data.error || 'Erreur';
    showMsg('msg-register', msg, true);
  }
});

applyAuthState();
checkHealth();
