// js/app.js - Supabase frontend integration for Benjo-SMS
// Reads SUPABASE_URL and SUPABASE_ANON_KEY from meta tags in index.html

const SUPABASE_URL = document.querySelector('meta[name="supabase-url"]').content;
const SUPABASE_ANON_KEY = document.querySelector('meta[name="supabase-anon-key"]').content;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error('Supabase URL or ANON key not set. Please set meta tags in index.html');
}

// Fixed: use global `supabase` from the CDN (not supabaseJs)
const supabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Basic UI helpers
function show(el){ if(el) el.style.display = '' }
function hide(el){ if(el) el.style.display = 'none' }
function q(id){ return document.getElementById(id) }

// Auth & session handling
async function initAuth(){
  // Check session
  const { data } = await supabase.auth.getSession();
  const session = data.session;
  if(session){
    onLogin(session.user);
  } else {
    // try to recover stored session via onAuthStateChange
  }

  supabase.auth.onAuthStateChange((event, session) => {
    if(session && session.user) onLogin(session.user);
    else onLogout();
  });
}

async function onLogin(user){
  // show account box
  show(q('accountNav'));
  show(q('walletNav'));
  hide(q('loginNav'));
  show(q('logoutNav'));

  await loadProfile();
  await loadWallet();
  await loadServices();
  await loadAccounts();
}

function onLogout(){
  hide(q('accountNav'));
  hide(q('walletNav'));
  show(q('loginNav'));
  hide(q('logoutNav'));
  if(q('walletBalance')) q('walletBalance').textContent = '₦0';
  if(q('accountName')) q('accountName').textContent = 'Name: -';
  if(q('accountEmail')) q('accountEmail').textContent = 'Email: -';
}

// Register / Login UI
function openAuth(mode='login'){
  const modal = q('authModal');
  const title = q('authTitle');
  const fullName = q('fullName');
  if(mode === 'register'){
    title.textContent = 'Create account';
    if(fullName) fullName.style.display = '';
  } else {
    title.textContent = 'Login';
    if(fullName) fullName.style.display = 'none';
  }
  if(modal) modal.style.display = 'flex';
}
function closeAuth(){ if(q('authModal')) q('authModal').style.display = 'none' }

async function submitAuth(e){
  e.preventDefault();
  const titleEl = q('authTitle');
  const title = titleEl ? titleEl.textContent : 'Login';
  const email = q('email') ? q('email').value : '';
  const password = q('password') ? q('password').value : '';
  const name = q('fullName') ? q('fullName').value : '';

  if(title.toLowerCase().includes('create')){
    // sign up
    const { data, error } = await supabase.auth.signUp({ email, password }, { data: { full_name: name }});
    if(error){ if(q('authMessage')){ q('authMessage').textContent = error.message; q('authMessage').className='message error'; } return }
    if(q('authMessage')){ q('authMessage').textContent = 'Sign-up successful. Check your email. You can log in after confirming.'; q('authMessage').className='message success'; }
  } else {
    // sign in
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if(error){ if(q('authMessage')){ q('authMessage').textContent = error.message; q('authMessage').className='message error'; } return }
    if(q('authMessage')){ q('authMessage').textContent = 'Logged in'; q('authMessage').className='message success'; }
    closeAuth();
  }
}

async function logout(){ await supabase.auth.signOut(); }

document.addEventListener('DOMContentLoaded', () => {
  initAuth();
  const form = q('authForm');
  if(form) form.addEventListener('submit', submitAuth);
});

// Profiles
async function loadProfile(){
  const { data: { session } } = await supabase.auth.getSession();
  if(!session) return;
  const uid = session.user.id;
  const { data, error } = await supabase.from('profiles').select('*').eq('id', uid).single();
  if(error){ console.warn('No profile found:', error.message); return }
  const profile = data;
  if(q('accountName')) q('accountName').textContent = `Name: ${profile.full_name || '-'} `;
  if(q('accountEmail')) q('accountEmail').textContent = `Email: ${profile.email || session.user.email}`;
  // show account box
  show(q('accountBox'));
}

// Wallet
async function loadWallet(){
  const { data: { session } } = await supabase.auth.getSession();
  if(!session) return;
  const uid = session.user.id;
  const { data, error } = await supabase.from('wallets').select('balance').eq('user_id', uid).single();
  if(error){ console.warn('wallet load error', error.message); if(q('walletBalance')) q('walletBalance').textContent = '₦0'; return }
  if(q('walletBalance')) q('walletBalance').textContent = `₦${Number(data.balance).toFixed(2)}`;
}

// Fund wallet via funding request
async function fundWallet(){
  // gather info using prompts (simple) - for production replace with a form/modal
  const amount = prompt('Enter amount to fund (NGN):');
  if(!amount) return;
  const method = prompt('Payment method (e.g. Bank transfer, USSD, Card):');
  if(!method) return;
  const reference = prompt('Payment reference or transaction ID:');
  if(!reference) return;

  // file input for proof
  const fileInput = document.createElement('input');
  fileInput.type = 'file';
  fileInput.accept = 'image/*';
  fileInput.click();
  fileInput.onchange = async () => {
    const file = fileInput.files[0];
    if(!file) return alert('No file selected');
    try{
      // upload to storage
      const filename = `${Date.now()}_${file.name}`;
      const { data: uploadData, error: uploadError } = await supabase.storage.from('payment_proofs').upload(filename, file);
      if(uploadError){ throw uploadError }
      const proof_path = uploadData.path;
      // create funding request row
      // Do NOT set user_id from client. The DB trigger sets user_id = auth.uid() server-side.
      const { data, error } = await supabase.from('funding_requests').insert([{
        amount: parseFloat(amount),
        method,
        reference,
        proof_path,
      }]);
      if(error) throw error;
      alert('Funding request submitted and is pending admin approval.');
    }catch(err){
      console.error(err);
      alert('Error submitting funding request: ' + err.message);
    }
  };
}

// Services & accounts
async function loadServices(){
  const { data, error } = await supabase.from('services').select('*').eq('is_active', true).order('created_at', { ascending: false });
  const container = q('serviceGrid');
  if(!container) return;
  container.innerHTML = '';
  if(error){ container.innerHTML = '<div class="empty">Error loading services</div>'; return }
  if(!data || data.length === 0){ container.innerHTML = '<div class="empty">No services available</div>'; return }
  data.forEach(s => {
    const div = document.createElement('div');
    div.className = 'service-card';
    div.innerHTML = `<div class="service-icon">🔧</div><h3>${s.name}</h3><p>${s.description || ''}</p><div class="price">₦${Number(s.price).toFixed(2)}</div>`;
    container.appendChild(div);
  });
}

async function loadAccounts(){
  const { data, error } = await supabase.from('account_products').select('id,platform,price,is_sold,metadata').eq('is_sold', false).order('created_at', { ascending: false });
  const container = q('accountProducts');
  if(!container) return;
  container.innerHTML = '';
  if(error){ container.innerHTML = '<div class="empty">Error loading accounts</div>'; return }
  if(!data || data.length === 0){ container.innerHTML = '<div class="empty">No accounts available</div>'; return }
  data.forEach(p => {
    const card = document.createElement('div');
    card.className = 'card';
    card.innerHTML = `<div class="card-icon">💼</div><h3>${p.platform} Account</h3><p>Price: ₦${Number(p.price).toFixed(2)}</p><button class="buy-btn">Buy</button>`;
    const btn = card.querySelector('button');
    btn.addEventListener('click', () => purchaseAccount(p.id));
    container.appendChild(card);
  });
}

// Purchase: call server-side RPC purchase_account_rpc(account_product_id)
async function purchaseAccount(productId){
  if(!confirm('Confirm purchase from wallet?')) return;
  try{
    const { data, error } = await supabase.rpc('purchase_account_rpc', { account_product_id: productId });
    if(error) throw error;
    // RPC returns order details and credentials
    alert('Purchase successful. Credentials will be displayed (if eligible).');
    console.log('purchase result', data);
    // refresh lists and wallet
    await loadWallet();
    await loadAccounts();
  }catch(err){
    console.error(err);
    alert('Purchase failed: ' + (err.message || JSON.stringify(err)));
  }
}

// Admin actions
async function adminApproveFunding(requestId, approve=true){
  if(!confirm((approve ? 'Approve' : 'Reject') + ' funding request?')) return;
  try{
    const { data, error } = await supabase.rpc('approve_funding_rpc', { fid: requestId, approve: approve });
    if(error) throw error;
    alert('Funding request processed.');
  }catch(err){
    console.error(err);
    alert('Error processing funding: ' + err.message);
  }
}

// Utilities
function scrollToAccount(){ location.hash = '#wallet'; }
function scrollToWallet(){ location.hash = '#wallet'; }
function chatAdmin(msg){ window.open('https://wa.me/?text=' + encodeURIComponent(msg), '_blank') }
function boostingChat(platform){ chatAdmin('I want a ' + platform + ' boosting service'); }

// Expose to window for inline onclick handlers
window.openAuth = openAuth;
window.closeAuth = closeAuth;
window.fundWallet = fundWallet;
window.loadWallet = loadWallet;
window.purchaseAccount = purchaseAccount;
window.loadServices = loadServices;
window.loadAccounts = loadAccounts;
window.viewCart = () => alert('Cart not implemented in this integration.');
window.logout = logout;
window.chatAdmin = chatAdmin;
window.boostingChat = boostingChat;
