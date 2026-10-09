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
    if (!token) { status.textContent="Restart launcher to connect"; return; }
    const response = await chrome.runtime.sendMessage({ action: name, token, data: {} });
    status.textContent = response?.payload?.message || response?.payload?.error || "No response";
    if (!response?.ok) status.title = status.textContent;
  }
  const panel = document.createElement("div");
  panel.style.cssText = "position:fixed;z-index:2147483647;bottom:76px;right:16px;max-width:540px;width:90vw;max-height:65vh;overflow:auto;background:#202936;color:white;padding:15px;border:1px solid #738095;border-radius:8px;box-shadow:0 5px 18px #0008;display:none;font:13px system-ui,sans-serif";
  const content = document.createElement("div");
  const close = document.createElement("button");
  close.textContent = "Close";
  close.onclick = () => panel.style.display = "none";
  panel.append(close, content);
  const show = () => { panel.style.display="block";content.replaceChildren(); };
  const line = text => { const p=document.createElement("p");p.textContent=text;content.appendChild(p); };
  const formButton = (text,handler) => {
    const b=document.createElement("button");
    b.textContent=text;b.onclick=handler;b.style.cssText="padding:8px;margin:6px;background:#475d78;color:white;border:1px solid #9daaba;border-radius:5px;cursor:pointer";
    content.appendChild(b);return b;
  };
  button("Keys", () => {
    show();
    line("Keys are encrypted locally for your Windows user. Do not paste tokens into chat.");
    const field = label => {
      const caption=document.createElement("label");caption.textContent=label;
      caption.style.cssText="display:block;margin:9px 0 4px";
      const input=document.createElement("input");input.type="password";input.autocomplete="off";
      input.style.cssText="display:block;box-sizing:border-box;width:100%;padding:8px;color:black;background:white";
      content.append(caption,input);return input;
    };
    const github=field("GitHub personal access token (repository read access)");
    const gitea=field("MyGitea2 API token (repository write access)");
    const saveButton=formButton("Save Keys",async()=>{
      if(!token){line("Launcher not connected. Restart MyGitea2 first.");return;}
      if(!github.value.trim()||!gitea.value.trim()){line("Both keys are required.");return;}
      saveButton.disabled=true;
      status.textContent="Saving encrypted keys...";
      try {
        const result=await chrome.runtime.sendMessage({action:"keys",token,data:{github:github.value.trim(),gitea:gitea.value.trim()}});
        if(!result?.ok){
          const message=result?.payload?.error||result?.payload?.message||"No response from launcher";
          status.textContent="Keys NOT saved";
          line("Save failed: "+message);
          return;
        }
        github.value="";gitea.value="";
        status.textContent="Keys saved and verified";
        line("Keys saved on this PC. You may close this panel and run Sync GitHub.");
      }catch(error){
        status.textContent="Keys NOT saved";
        line("Save failed: "+String(error.message||error));
      }finally {saveButton.disabled=false;}
    });
  });
  button("Sync GitHub", async () => {
    if(!token){status.textContent="Restart launcher to connect";return;}
    show();line("Preview only: no repositories imported until you choose one.");
    status.textContent="Loading preview...";
    let response;
    try{response=await chrome.runtime.sendMessage({action:"preview",token,data:{}});}
    catch(error){status.textContent=String(error);return;}
    if(!response?.ok){status.textContent=response?.payload?.error||"Preview failed";return;}
    const result=response.payload;
    status.textContent="Preview ready";
    line(String(result.github_total)+" GitHub repositories, "+String(result.skipped)+" skipped, "+String(result.missing?.length||0)+" missing. Destination: "+result.gitea_user);
    if(!result.missing?.length)return;
    const select=document.createElement("select");
    select.style.cssText="width:100%;padding:9px;color:black;background:white";
    for(const repo of result.missing){
      const option=document.createElement("option");option.value=repo.full_name;
      option.textContent=repo.full_name+(repo.private?" (private)":"");
      select.appendChild(option);
    }
    content.appendChild(select);
    formButton("Import only selected repository",async()=>{
      const name=select.value;
      if(!confirm("Import "+name+" into MyGitea2?"))return;
      status.textContent="Submitting import...";
      const response=await chrome.runtime.sendMessage({action:"import",token,data:{full_name:name}});
      status.textContent=response?.ok?"Migration submitted":(response?.payload?.error||"Import failed");
      if(response?.ok)line("Migration submitted. Check Gitea for its result before importing another.");
    });
  });
  document.documentElement.appendChild(panel);
  button("Stop Gitea", () => action("stop"));
  bar.appendChild(status);
  document.documentElement.appendChild(bar);
})();
