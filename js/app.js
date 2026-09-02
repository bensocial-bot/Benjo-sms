/* =========================================================
   BENJO-SMS — js/app.js
   Supabase-compatible frontend
   ========================================================= */
const SUPABASE_URL =
  document.querySelector('meta[name="supabase-url"]')?.content?.trim();
const SUPABASE_ANON_KEY =
  document.querySelector('meta[name="supabase-anon-key"]')?.content?.trim();
if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error(
    "Supabase URL or ANON key is missing. Check the meta tags in index.html."
  );
}
const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_ANON_KEY
);
/* =========================================================
   HELPERS
   ========================================================= */
function show(el) {
  if (el) el.style.display = "";
}
function hide(el) {
  if (el) el.style.display = "none";
}
function q(id) {
  return document.getElementById(id);
}
function formatNaira(amount) {
  return `₦${Number(amount || 0).toLocaleString("en-NG", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })}`;
}
function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
async function getCurrentUser() {
  const { data, error } = await supabaseClient.auth.getSession();
  if (error) {
    console.error("Session error:", error.message);
    return null;
  }
  return data?.session?.user || null;
}
/* =========================================================
   AUTH
   ========================================================= */
async function initAuth() {
  const { data, error } = await supabaseClient.auth.getSession();
  if (error) {
    console.error("Auth session error:", error.message);
    return;
  }
  const session = data?.session;
  if (session?.user) {
    await onLogin(session.user);
  } else {
    onLogout();
  }
  supabaseClient.auth.onAuthStateChange(async (event, newSession) => {
    if (newSession?.user) {
      await onLogin(newSession.user);
    } else {
      onLogout();
    }
  });
}
async function onLogin(user) {
  show(q("accountNav"));
  show(q("walletNav"));
  hide(q("loginNav"));
  show(q("logoutNav"));
  await loadProfile();
  await loadWallet();
  await loadServices();
  await loadAccounts();
}
function onLogout() {
  hide(q("accountNav"));
  hide(q("walletNav"));
  show(q("loginNav"));
  hide(q("logoutNav"));
  if (q("walletBalance")) {
    q("walletBalance").textContent = "₦0.00";
  }
  if (q("accountName")) {
    q("accountName").textContent = "Name: -";
  }
  if (q("accountEmail")) {
    q("accountEmail").textContent = "Email: -";
  }
  hide(q("accountBox"));
}
/* =========================================================
   AUTH FORMS
   ========================================================= */
function openAuth(mode = "login") {
  const modal = q("authModal");
  const title = q("authTitle");
  const fullName = q("fullName");
  if (mode === "register") {
    if (title) title.textContent = "Create account";
    if (fullName) show(fullName);
  } else {
    if (title) title.textContent = "Login";
    if (fullName) hide(fullName);
  }
  if (modal) {
    modal.style.display = "flex";
  }
}
function closeAuth() {
  if (q("authModal")) {
    q("authModal").style.display = "none";
  }
}
async function submitAuth(e) {
  e.preventDefault();
  const titleEl = q("authTitle");
  const title = titleEl
    ? titleEl.textContent || "Login"
    : "Login";
  const email = q("email")?.value?.trim() || "";
  const password = q("password")?.value || "";
  const name = q("fullName")?.value?.trim() || "";
  const messageEl = q("authMessage");
  if (!email || !password) {
    if (messageEl) {
      messageEl.textContent = "Enter your email and password.";
      messageEl.className = "message error";
    }
    return;
  }
  try {
    if (title.toLowerCase().includes("create")) {
      const { error } = await supabaseClient.auth.signUp({
        email,
        password,
        options: {
          data: {
            full_name: name
          }
        }
      });
      if (error) throw error;
      if (messageEl) {
        messageEl.textContent =
          "Sign-up successful. Check your email if email confirmation is enabled.";
        messageEl.className = "message success";
      }
      return;
    }
    const { error } =
      await supabaseClient.auth.signInWithPassword({
        email,
        password
      });
    if (error) throw error;
    if (messageEl) {
      messageEl.textContent = "Logged in successfully.";
      messageEl.className = "message success";
    }
    closeAuth();
  } catch (err) {
    console.error("Authentication error:", err);
    if (messageEl) {
      messageEl.textContent =
        err?.message || "Authentication failed.";
      messageEl.className = "message error";
    }
  }
}
async function logout() {
  const { error } = await supabaseClient.auth.signOut();
  if (error) {
    console.error("Logout error:", error.message);
    alert("Logout failed: " + error.message);
  }
}
/* =========================================================
   PROFILE
   ========================================================= */
async function loadProfile() {
  const user = await getCurrentUser();
  if (!user) return;
  const { data, error } = await supabaseClient
    .from("profiles")
    .select("id,email,full_name,username,is_admin,role")
    .eq("id", user.id)
    .maybeSingle();
  if (error) {
    console.warn("Profile load error:", error.message);
    return;
  }
  if (!data) {
    console.warn("No profile found for user:", user.id);
    return;
  }
  if (q("accountName")) {
    q("accountName").textContent =
      `Name: ${data.full_name || data.username || "-"}`;
  }
  if (q("accountEmail")) {
    q("accountEmail").textContent =
      `Email: ${data.email || user.email || "-"}`;
  }
  show(q("accountBox"));
}
/* =========================================================
   WALLET
   Source of truth: wallets.balance
   ========================================================= */
async function loadWallet() {
  const user = await getCurrentUser();
  if (!user) return;
  const { data, error } = await supabaseClient
    .from("wallets")
    .select("balance")
    .eq("user_id", user.id)
    .maybeSingle();
  if (error) {
    console.warn("Wallet load error:", error.message);
    if (q("walletBalance")) {
      q("walletBalance").textContent = "₦0.00";
    }
    return;
  }
  const balance = data?.balance || 0;
  if (q("walletBalance")) {
    q("walletBalance").textContent = formatNaira(balance);
  }
}
/* =========================================================
   FUND WALLET
   Uses:
   payment-proofs bucket
   funding_requests table
   create_funding_request_secure()
   ========================================================= */
async function fundWallet() {
  const user = await getCurrentUser();
  if (!user) {
    alert("Please login first.");
    openAuth("login");
    return;
  }
  const amountInput = prompt("Enter amount to fund (NGN):");
  if (!amountInput) return;
  const amount = Number(
    String(amountInput)
      .replace(/,/g, "")
      .trim()
  );
  if (!Number.isFinite(amount) || amount <= 0) {
    alert("Please enter a valid amount.");
    return;
  }
  const method = prompt(
    "Payment method (e.g. Bank Transfer, USSD, Card):"
  );
  if (!method || !method.trim()) {
    alert("Payment method is required.");
    return;
  }
  const reference = prompt(
    "Payment reference / transaction ID:"
  );
  if (!reference || !reference.trim()) {
    alert("Payment reference is required.");
    return;
  }
  const fileInput = document.createElement("input");
  fileInput.type = "file";
  fileInput.accept = "image/*,.pdf";
  fileInput.onchange = async () => {
    const file = fileInput.files?.[0];
    if (!file) {
      alert("No payment proof selected.");
      return;
    }
    try {
      const safeName = file.name
        .replace(/[^a-zA-Z0-9._-]/g, "_")
        .substring(0, 100);
      const filePath =
        `${user.id}/${Date.now()}_${safeName}`;
      const {
        data: uploadData,
        error: uploadError
      } = await supabaseClient.storage
        .from("payment-proofs")
        .upload(filePath, file, {
          cacheControl: "3600",
          upsert: false
        });
      if (uploadError) {
        throw uploadError;
      }
      const proofPath =
        uploadData?.path || filePath;
      const {
        data,
        error
      } = await supabaseClient.rpc(
        "create_funding_request_secure",
        {
          p_amount: amount,
          p_payment_method: method.trim(),
          p_payment_reference: reference.trim(),
          p_proof_url: proofPath
        }
      );
      if (error) {
        await supabaseClient.storage
          .from("payment-proofs")
          .remove([proofPath]);
        throw error;
      }
      const result = Array.isArray(data)
        ? data[0]
        : data;
      if (!result?.success) {
        await supabaseClient.storage
          .from("payment-proofs")
          .remove([proofPath]);
        throw new Error(
          result?.message ||
          "Funding request could not be created."
        );
      }
      alert(
        "Funding request submitted successfully.\n\n" +
        "Your payment is now pending admin approval."
      );
      await loadWallet();
    } catch (err) {
      console.error("Funding error:", err);
      alert(
        "Error submitting funding request:\n" +
        (err?.message || "Unknown error")
      );
    }
  };
  fileInput.click();
}
/* =========================================================
   SERVICES
   ========================================================= */
async function loadServices() {
  const container = q("serviceGrid");
  if (!container) return;
  container.innerHTML =
    '<div class="empty">Loading services...</div>';
  const {
    data,
    error
  } = await supabaseClient
    .from("services")
    .select(
      "id,name,description,price,delivery_information,available,category,platform,active,created_at"
    )
    .eq("active", true)
    .eq("available", true)
    .order("created_at", {
      ascending: false
    });
  container.innerHTML = "";
  if (error) {
    console.error("Services error:", error.message);
    container.innerHTML =
      '<div class="empty">Error loading services</div>';
    return;
  }
  if (!data || data.length === 0) {
    container.innerHTML =
      '<div class="empty">No services available</div>';
    return;
  }
  data.forEach((service) => {
    const div = document.createElement("div");
    div.className = "service-card";
    const platform =
      service.platform
        ? `<small>${escapeHtml(service.platform)}</small>`
        : "";
    const category =
      service.category
        ? `<small>${escapeHtml(service.category)}</small>`
        : "";
    div.innerHTML = `
      <div class="service-icon">🔧</div>
      <h3>${escapeHtml(service.name)}</h3>
      <p>${escapeHtml(service.description || "")}</p>
      <div class="service-meta">
        ${platform}
        ${category}
      </div>
      <div class="price">
        ${formatNaira(service.price)}
      </div>
      <button
        class="buy-service-btn"
        type="button"
      >
        Buy
      </button>
    `;
    const button =
      div.querySelector(".buy-service-btn");
    if (button) {
      button.addEventListener("click", () => {
        purchaseService(service.id);
      });
    }
    container.appendChild(div);
  });
}
/* =========================================================
   SERVICE PURCHASE
   Uses create_wallet_order RPC
   ========================================================= */
async function purchaseService(serviceId) {
  const user = await getCurrentUser();
  if (!user) {
    alert("Please login first.");
    openAuth("login");
    return;
  }
  const confirmed = confirm(
    "Confirm purchase of this service using your wallet?"
  );
  if (!confirmed) return;
  try {
    const {
      data,
      error
    } = await supabaseClient.rpc(
      "create_wallet_order",
      {
        p_service_id: serviceId,
        p_order_details: {}
      }
    );
    if (error) throw error;
    const result = Array.isArray(data)
      ? data[0]
      : data;
    console.log(
      "Service purchase result:",
      result
    );
    alert(
      "Service purchased successfully."
    );
    await loadWallet();
    await loadServices();
  } catch (err) {
    console.error(
      "Service purchase error:",
      err
    );
    alert(
      "Purchase failed:\n" +
      (err?.message || "Unknown error")
    );
  }
}
/* =========================================================
   ACCOUNTS
   IMPORTANT:
   DO NOT query account_products directly.
   Login/password must NEVER be exposed to normal users.
   Uses secure:
   get_available_accounts()
   ========================================================= */
async function loadAccounts() {
  const container = q("accountProducts");
  if (!container) return;
  container.innerHTML =
    '<div class="empty">Loading accounts...</div>';
  try {
    const {
      data,
      error
    } = await supabaseClient.rpc(
      "get_available_accounts"
    );
    if (error) {
      throw error;
    }
    container.innerHTML = "";
    if (!data || data.length === 0) {
      container.innerHTML =
        '<div class="empty">No accounts available</div>';
      return;
    }
    data.forEach((account) => {
      const card =
        document.createElement("div");
      card.className = "card";
      const title =
        account.platform
          ? `${account.platform} Account`
          : account.service_name || "Account";
      card.innerHTML = `
        <div class="card-icon">💼</div>
        <h3>
          ${escapeHtml(title)}
        </h3>
        <p>
          Price:
          <strong>
            ${formatNaira(account.price)}
          </strong>
        </p>
        ${
          account.description
            ? `
              <p>
                ${escapeHtml(account.description)}
              </p>
            `
            : ""
        }
        <button
          class="buy-btn"
          type="button"
        >
          Buy Account
        </button>
      `;
      const button =
        card.querySelector(".buy-btn");
      if (button) {
        button.addEventListener(
          "click",
          () => {
            purchaseAccount(account.id);
          }
        );
      }
      container.appendChild(card);
    });
  } catch (err) {
    console.error(
      "Accounts error:",
      err
    );
    container.innerHTML =
      '<div class="empty">Error loading accounts</div>';
  }
}
/* =========================================================
   ACCOUNT PURCHASE
   Uses purchase_account_secure()
   ========================================================= */
async function purchaseAccount(productId) {
  const user = await getCurrentUser();
  if (!user) {
    alert("Please login first.");
    openAuth("login");
    return;
  }
  const confirmed = confirm(
    "Confirm purchase of this account using your wallet?"
  );
  if (!confirmed) return;
  try {
    const {
      data,
      error
    } = await supabaseClient.rpc(
      "purchase_account_secure",
      {
        p_account_product_id: productId,
        p_order_details: {}
      }
    );
    if (error) throw error;
    const result = Array.isArray(data)
      ? data[0]
      : data;
    if (!result?.success) {
      throw new Error(
        result?.message ||
        "Account purchase failed."
      );
    }
    alert(
      "Account purchased successfully.\n\n" +
      "Your order has been created. " +
      "Credentials will be available through the secure order system."
    );
    console.log(
      "Account purchase:",
      result
    );
    await loadWallet();
    await loadAccounts();
  } catch (err) {
    console.error(
      "Account purchase error:",
      err
    );
    alert(
      "Purchase failed:\n" +
      (err?.message || "Unknown error")
    );
  }
}
/* =========================================================
   ADMIN FUNDING APPROVAL
   Uses approve_funding_secure()
   ========================================================= */
async function adminApproveFunding(
  requestId,
  approve = true,
  adminNote = null
) {
  const confirmed = confirm(
    (approve ? "Approve" : "Reject") +
    " this funding request?"
  );
  if (!confirmed) return;
  try {
    const {
      data,
      error
    } = await supabaseClient.rpc(
      "approve_funding_secure",
      {
        p_request_id: requestId,
        p_approve: approve,
        p_admin_note: adminNote
      }
    );
    if (error) throw error;
    const result = Array.isArray(data)
      ? data[0]
      : data;
    if (!result?.success) {
      throw new Error(
        result?.message ||
        "Funding request could not be processed."
      );
    }
    alert(
      result.message ||
      "Funding request processed successfully."
    );
    await loadWallet();
  } catch (err) {
    console.error(
      "Admin funding error:",
      err
    );
    alert(
      "Error processing funding:\n" +
      (err?.message || "Unknown error")
    );
  }
}
/* =========================================================
   NAVIGATION / CHAT
   ========================================================= */
function scrollToAccount() {
  location.hash = "#accounts";
}
function scrollToWallet() {
  location.hash = "#wallet";
}
function chatAdmin(msg) {
  const message =
    msg ||
    "Hello Benjo-SMS, I need assistance.";
  const url =
    "https://wa.me/?text=" +
    encodeURIComponent(message);
  window.open(url, "_blank");
}
function boostingChat(platform) {
  chatAdmin(
    `Hello Benjo-SMS, I want a ${platform} boosting service.`
  );
}
/* =========================================================
   DOM READY
   ========================================================= */
document.addEventListener(
  "DOMContentLoaded",
  async () => {
    const form = q("authForm");
    if (form) {
      form.addEventListener(
        "submit",
        submitAuth
      );
    }
    await initAuth();
  }
);
/* =========================================================
   GLOBAL FUNCTIONS FOR index.html
   ========================================================= */
window.openAuth = openAuth;
window.closeAuth = closeAuth;
window.fundWallet = fundWallet;
window.loadWallet = loadWallet;
window.loadServices = loadServices;
window.loadAccounts = loadAccounts;
window.purchaseAccount = purchaseAccount;
window.purchaseService = purchaseService;
window.adminApproveFunding = adminApproveFunding;
window.logout = logout;
window.chatAdmin = chatAdmin;
window.boostingChat = boostingChat;
window.scrollToAccount = scrollToAccount;
window.scrollToWallet = scrollToWallet;
/*
 * Keep viewCart available so existing HTML does not break.
 */
window.viewCart = function () {
  alert(
    "Your wallet purchases do not require a shopping cart. " +
    "Select the account/service you want and purchase directly."
  );
};
