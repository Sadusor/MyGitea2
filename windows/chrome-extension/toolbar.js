(() => {
  if (window.top !== window || document.getElementById("mygitea2-toolbar")) return;
  const match = location.hash.match(/(?:^#|&)mygitea2-token=([a-f0-9-]{36})/i);
  const key = "mygitea2-session-token";
  if (match) {
    sessionStorage.setItem(key, match[1]);
    history.replaceState(null, "", location.pathname + location.search);
  }
  const token = sessionStorage.getItem(key);
  const bar = document.createElement("div");
  bar.id = "mygitea2-toolbar";
  bar.style.cssText = "position:fixed;z-index:2147483647;bottom:16px;right:16px;background:#202936;color:#fff;padding:10px 14px;border:1px solid #738095;border-radius:9px;box-shadow:0 4px 22px #0007;display:flex;align-items:center;gap:9px;font:13px system-ui,sans-serif";
  const label = document.createElement("span");
  label.textContent = "MyGitea2";
  bar.appendChild(label);
  function button(text, handler) {
    const b = document.createElement("button");
    b.textContent = text;
    b.type = "button";
    b.style.cssText = "background:#37485d;color:white;border:1px solid #8994a3;border-radius:5px;padding:6px 9px;cursor:pointer";
    b.addEventListener("click", handler);
    bar.appendChild(b);
    return b;
  }
  let auto = sessionStorage.getItem("mygitea2-auto-refresh") === "yes";
  const autoButton = button("Auto Refresh: " + (auto ? "ON" : "OFF"), () => {
    auto = !auto;
    sessionStorage.setItem("mygitea2-auto-refresh", auto ? "yes" : "no");
    autoButton.textContent = "Auto Refresh: " + (auto ? "ON" : "OFF");
  });
  setInterval(() => {
    if (auto && !document.hidden && !document.querySelector("textarea:focus,input:focus,[contenteditable=true]:focus")) {
      location.reload();
    }
  }, 60000);
  const status = document.createElement("span");
  status.textContent = token ? "Ready" : "Controls need launcher reconnect";
  status.style.maxWidth = "260px";
  status.style.overflow = "hidden";
  status.style.textOverflow = "ellipsis";
  async function action(name) {
    if (!token) { status.textContent = "Restart MyGitea2 launcher to connect"; return; }
    if (name === "stop" && !confirm("Stop only MyGitea2?")) return;
    status.textContent = name === "pull" ? "Pulling..." : "Stopping...";
    const response = await chrome.runtime.sendMessage({ action: name, token });
    status.textContent = response?.detail || "No response";
    if (!response?.ok) status.title = status.textContent;
  }
  button("Pull GitHub", () => action("pull"));
  button("Stop Gitea", () => action("stop"));
  bar.appendChild(status);
  document.documentElement.appendChild(bar);
})();
