chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!sender.tab || !sender.tab.url?.startsWith("http://127.0.0.1:3001/")) return;
  if (!["pull", "stop"].includes(message?.action) || typeof message.token !== "string") return;
  fetch("http://127.0.0.1:3002/" + message.action, {
    method: "POST",
    headers: { "Authorization": "Bearer " + message.token }
  }).then(async response => {
    const detail = await response.text();
    sendResponse({ ok: response.ok, detail });
  }).catch(error => sendResponse({ ok: false, detail: String(error) }));
  return true;
});
