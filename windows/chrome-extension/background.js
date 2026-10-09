chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!sender.tab || !sender.url?.startsWith("http://127.0.0.1:3001/")) {
    sendResponse({ ok: false, payload: { error: "Request origin is not MyGitea2" } });
    return false;
  }
  const actions = ["stop", "keys", "preview", "import"];
  if (!actions.includes(message?.action) || typeof message.token !== "string") return;
  const data = message.data && typeof message.data === "object" ? message.data : {};
  fetch("http://127.0.0.1:3002/" + message.action, {
    method: "POST",
    headers: {
      "Authorization": "Bearer " + message.token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(data).replace(/[^\x00-\x7F]/g, c => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"))
  }).then(async response => {
    const raw = await response.text();
    let payload;
    try { payload = JSON.parse(raw); } catch { payload = { message: raw }; }
    sendResponse({ ok: response.ok, payload });
  }).catch(error => sendResponse({ ok: false, payload: { error: String(error) } }));
  return true;
});
