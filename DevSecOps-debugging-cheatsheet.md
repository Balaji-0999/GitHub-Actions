# DevSecOps Pipeline Debugging Cheatsheet
### GitHub Actions → EC2 SSH Deploy → Docker → Flask App

A complete record of every problem that came up while building this pipeline — what the error was, why it happened, how it was fixed, and the logic behind each command.

---

## 1. Secrets weren't reaching the reusable workflow

**Error/Symptom:**
```
Username: "", Password: ""  (empty in debug log)
ssh: unable to authenticate, attempted methods [none], no supported methods remain
```

**Why it happened:**
`devsecops-pipeline.yml` was calling the reusable workflow (`deploy-to-server.yml`) with `uses:`. In GitHub Actions, **child workflows don't automatically get the parent's secrets** — each reusable workflow runs in its own sandbox.

**Solution:**
```yaml
deploy:
    uses: ./.github/workflows/deploy-to-server.yml
    secrets: inherit
```

**Logic:** `secrets: inherit` explicitly tells GitHub "pass along whatever secrets the caller has to the child." Without it, `secrets.XYZ` always resolves to an empty string inside the child workflow.

---

## 2. A secret's value was corrupted (multi-line password)

**Error/Symptom:**
```
Password: "***
***
***
...  (repeated 18-27 times)
```

**Why it happened:**
While copy-pasting the password, an extra newline/Enter got copied along with it. SSH expects a clean single-line string — a newline in the middle corrupts the whole auth string.

**Solution:**
Deleted the secret, typed the password manually in Notepad (not pasted), selected only the exact text (no trailing Enter/space), and re-saved it as the secret.

**Logic:** If the debug log shows the password/key as a **single** `***` line, it's clean. Multiple lines is itself the signal of multi-line corruption.

---

## 3. The server wasn't accepting password authentication at all

**Error/Symptom:**
Password was correct and clean — still `attempted methods [none]`.

**Why it happened:**
In EC2 Ubuntu's `/etc/ssh/sshd_config`, `#PasswordAuthentication yes` was **commented out** (default is `no`). The server had already decided it wouldn't accept passwords, period.

**Commands:**
```bash
# Check the current setting
sudo grep -i passwordauthentication /etc/ssh/sshd_config

# Fix it (remove the comment)
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Restart to apply
sudo systemctl restart ssh
```

**Logic:** `sed -i 's/old/new/' file` finds and replaces text inside a file (`-i` = in-place, edits the file directly). After changing SSH config, **restarting the service is mandatory** — otherwise the old settings stay active in memory.

---

## 4. Username secret came out empty

**Error/Symptom:**
```
Username: ""
```

**Why it happened:**
The `EC2_USERNAME` secret's value got accidentally deleted while editing, or was set to the wrong format (`ubuntu@ip-172-31-22-228` — a full connection string) when it should have just been `ubuntu`.

**Solution:**
```
EC2_USERNAME = ubuntu   (username only — no IP or @)
```

**Logic:** `username@host` is only written together when typing an `ssh` command directly in a terminal. In a workflow, **`username` and `host` are separate fields** — putting both in one breaks the SSH client.

---

## 5. Private key was put in the `password` field instead of `key`

**Error/Symptom:**
```
Key: ""
Password: "***  (27+ lines — the entire private key content)
```

**Why it happened:**
```yaml
password: ${{ secrets.SSH_PRIVATE_KEY }}   # wrong field
```

**Solution:**
```yaml
key: ${{ secrets.SSH_PRIVATE_KEY }}   # correct field
```

**Logic:** `appleboy/ssh-action` has two **separate authentication methods** — password-based and key-based. A private key always goes in the `key:` field, never `password:`. The field name defines its purpose.

---

## 6. Typo in the docker login flag

**Error/Symptom:**
```
unknown flag: --passwpord-stdin
```

**Why it happened:** Typo — `--password-stdin` misspelled as `--passwpord-stdin` (letters out of order).

**Solution:**
```bash
echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
```

**Logic:** `--password-stdin` tells Docker the password will come via **stdin (a pipe)** instead of being typed — this keeps the password from showing up in plaintext in shell history/process lists, a security best practice.

---

## 7. Image tag was empty

**Error/Symptom:**
```
unable to get image 'balaji8800/github-actions-app:': invalid reference format
```

**Why it happened:** In `docker pull image:$TAG`, the `$TAG` variable was never set (empty), so it became `image:` (nothing after the colon) — Docker considers this format invalid.

**Solution:** For simplicity, hardcode it:
```bash
docker pull balaji8800/github-actions-app:latest
```

**Logic:** A Docker image reference always follows the `name:tag` format. If a variable (`$TAG`) is undefined/empty, the shell substitutes it with a blank string, leaving the tag missing.

---

## 8. `cd ~DevOps` — invalid path syntax

**Error/Symptom:** Shell error / folder not found.

**Why it happened:** `~` is only valid combined with `/` (home) or a username (`~username`). `~DevOps` makes the shell look for a user literally named "DevOps," which doesn't exist.

**Solution:**
```bash
cd ~/DevOps
```

**Logic:** In Bash, `~` is a special character representing the home directory — it must be **separated from the folder name with a slash (`/`)**.

---

## 9. `docker-compose-v2` — wrong package name

**Error/Symptom:** `apt-get install` fails, package not found.

**Why it happened:** No package by that name exists in the Ubuntu repositories.

**Solution:**
```bash
sudo apt-get update && sudo apt-get install docker.io docker-compose-plugin -y
```

**Logic:** The actual Ubuntu package name for Docker Compose v2 (which provides the `docker compose` command, no hyphen) is `docker-compose-plugin`.

---

## 10. `newgrp docker` was blocking/hanging the script

**Error/Symptom:** Commands after this line in the non-interactive SSH script weren't executing properly.

**Why it happened:** `newgrp` starts a **new interactive shell** — which, in a non-interactive SSH script, ends up consuming the rest of the script's lines as its own stdin.

**Solution:** Remove the `newgrp docker` line entirely — the SSH action's **next step is a brand-new session**, so updated group membership is picked up automatically.

**Logic:** Group membership changes don't apply instantly in the current shell — they're reflected automatically in a new session (a new SSH connection), so `newgrp` wasn't needed at all here.

---

## 11. `docker compose build` failed — Dockerfile missing

**Error/Symptom:**
```
failed to solve: failed to read dockerfile: open Dockerfile: no such file or directory
```

**Why it happened:** `docker-compose.yml` had `build: .`, but only `docker-compose.yml` was copied to the server (via scp) — the Dockerfile/source code was never copied.

**Solution:** Remove `build: .` and the `--build` flag:
```yaml
services:
  web:
    image: ${DOCKERHUB_USERNAME}/github-actions-app:${DOCKER_TAG}
```
```bash
docker compose up -d   # without --build
```

**Logic:** When the image is **already being pulled from Docker Hub**, `build`/`--build` aren't needed at all — they tell Docker "rebuild this locally," which fails when the source code isn't even present on the server.

---

## 12. `DOCKER_TAG` environment variable wasn't set

**Error/Symptom:**
```
The "DOCKER_TAG" variable is not set. Defaulting to a blank string.
unable to get image '...:' invalid reference format
```

**Why it happened:** `docker-compose.yml` referenced `${DOCKER_TAG}`, but the SSH script never **exported** this variable.

**Solution:**
```bash
export DOCKER_TAG=latest
```

**Logic:** Whenever a compose file uses `${VAR}` syntax, it needs an environment variable of that exact name **already defined in the shell** — Compose doesn't guess values on its own.

---

## 13. Flask app was listening on `127.0.0.1` instead of `0.0.0.0`

**Error/Symptom:**
```
Running on http://127.0.0.1:80
curl: (56) Recv failure: Connection reset by peer
```

**Why it happened:** `app.run(port=80)` — without specifying `host`, Flask defaults to `127.0.0.1` (only reachable from inside the same machine/container). No request from outside the container was accepted.

**Solution:**
```python
app.run(host="0.0.0.0", port=80)
```

**Logic:** `0.0.0.0` means "listen on all network interfaces" — this lets requests from outside the container (the host machine, the internet) get through. `127.0.0.1` is like only being able to talk to yourself.

---

## 14. Gunicorn crash-loop — "Address already in use"

**Error/Symptom:**
```
Address already in use
Port 80 is in use by another program.
[Worker exiting] → [new worker boots] → repeat...
```

**Why it happened (root cause, occurred twice):**
`app.run(port=80)` at the bottom of `app.py` was written **without a guard** (at the top level of the file). When gunicorn **imports** this file (via `app:app`), Python executes the entire file top to bottom — so Flask's own dev server also tries to bind to port 80 immediately, while a gunicorn worker has already claimed that port. The two collide.

**Solution:**
```python
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80)
```

**Logic:** `if __name__ == "__main__":` is a guard that's only `True` when the file is run **directly** (`python app.py`). When another module **imports** it (as gunicorn does), this condition is `False`, so the line inside gets skipped.

**Important lesson:** This bug came back a **second time** because during a later edit (fixing lint errors), the guard line got accidentally reverted. **Always re-check the full file content after any full-file replace.**

---

## 15. `gunicorn` executable not found

**Error/Symptom:**
```
exec: "gunicorn": executable file not found in $PATH
```

**Why it happened:** `gunicorn` wasn't listed in `requirements.txt`, so `pip install -r requirements.txt` never installed it.

**Solution:** Add a line to `requirements.txt`:
```
gunicorn
```

**Logic:** A Dockerfile's `CMD ["gunicorn", ...]` only works if gunicorn is actually **installed** inside the image. `pip install` only installs what's listed in `requirements.txt`.

---

## 16. Port mismatch in the Dockerfile

**Error/Symptom:** The app started but on the wrong port, not matching `EXPOSE`/compose.

**Why it happened:**
```dockerfile
CMD ["gunicorn","--bind", "0.0.0.0:5000", "app:app"]   # 5000
EXPOSE 80                                                # 80
```
`docker-compose.yml` had `80:80` mapping, but gunicorn inside was binding to `5000`.

**Solution:** All three places must use the same port:
```dockerfile
EXPOSE 80
CMD ["gunicorn", "--bind", "0.0.0.0:80", "app:app"]
```

**Logic:** `EXPOSE`, the Dockerfile's `CMD`/bind port, and docker-compose's port mapping (`HOST:CONTAINER`) form one **chain**. If any one is different, traffic doesn't get routed to the right place.

---

## 17. Flake8 lint errors — duplicate code

**Error/Symptom:**
```
F811 redefinition of unused 'render_template' from line 1
E402 module level import not at top of file
```

**Why it happened:** While editing the file, the old code wasn't deleted and the new code got pasted below it — the entire content (imports + functions) got duplicated.

**How it was identified:** Error format = `file:line:column: code message`
- `F811` = "found a redefinition of something" — the code itself always tells you the problem type
- The line number points directly to where to look in the file

**Solution:** Select and delete the entire file's contents, then paste the clean version.

**Logic:** Linters (`flake8`, `pylint`) always follow the `filename:line:column: code description` format — whatever the error, check the **line number** first; 90% of the time it gives the answer directly.

---

## 18. Whitespace / missing newline warnings

**Error/Symptom:**
```
W293 blank line contains whitespace
W292 no newline at end of file
```

**Why it happened:** There were invisible trailing spaces at the end of the file, and the file ended without a proper newline.

**Solution (manual):** Remove trailing spaces on the last line, add one Enter at the end of the file.

**Solution (permanent, VS Code settings.json):**
```json
"files.trimTrailingWhitespace": true,
"files.insertFinalNewline": true,
"files.trimFinalNewlines": true
```

**Logic:** These are purely style/formatting rules (they don't break code logic), but linters are strict — enabling these VS Code settings fixes it **automatically** on save, so you never have to check manually again.

---

## 19. Bandit security warning — `0.0.0.0` binding

**Error/Symptom:**
```
[B104:hardcoded_bind_all_interfaces] Possible binding to all interfaces.
Severity: Medium
```

**Why it happened:** Bandit (a security scanner) flags every `host="0.0.0.0"` because it **exposes all interfaces** — without knowing the context that this is a public web app where that's exactly what's needed.

**Solution (line-specific suppress):**
```python
app.run(host="0.0.0.0", port=80)  # nosec B104
```

**Logic:** The `# nosec B104` comment tells bandit "this specific warning is intentional here, skip it." This is better than disabling the check globally (via a `.bandit` config) — only this one line is exempted, the rest of the file keeps being scanned. **In DevSecOps, you don't blindly ignore a security warning — you consciously suppress it (with a documented reason).**

---

## 20. Couldn't connect from the browser (real cause: the app was crash-looping)

**Symptom:** Both `curl` and the browser hung/timed out, no error shown.

**Debugging path that was followed (the lesson here):**
1. `docker ps` → container showed "Up" (misleading — only the master process was alive)
2. Checked Security Group → was correct (`0.0.0.0/0`, port 80)
3. Checked Network ACL → default, everything allowed
4. Checked `ufw status` → inactive
5. Spun up a new EC2 instance to test → same problem (this ruled out it being instance-specific)
6. Tried a different route, `/health` → also hung
7. Tested outbound (`curl https://google.com`) → instant response (internet/DNS was fine)
8. Checked `docker logs` → **this is where the real culprit was found**: crash-loop ("Address already in use")

**The biggest lesson:** When the app shows as "up" but doesn't respond, **check `docker logs` first** — everything else (Security Group, NACL, firewall, spinning up a new instance) was a time-consuming detour that turned out to be irrelevant. Logs almost always reveal the **root cause** when it's an application-level issue.

---

## Master Debugging Checklist (use this directly next time)

Whenever SSH/deploy/app access fails, check things **in this order**:

1. **`docker ps`** — is the container running, or is it crash-looping?
2. **`docker logs <container>`** — any repeating error/crash visible?
3. **`docker logs --tail 50 <container>`** — if logs are huge, just check the recent ones
4. **`curl -v --max-time 10 localhost/<route>`** — does the app respond on its own (from inside the server)?
5. **Check secrets** (with `debug: true`) — is any secret empty/corrupted?
6. **Server-side config** (`sshd_config`, `ufw status`) — is some setting blocking things?
7. **AWS Security Group** — is the right port, right source (`0.0.0.0/0`) allowed?
8. **Network ACL** — any custom restriction at the subnet level?
9. **Outbound test** (`curl https://google.com`) — if the app makes external calls

**Golden rule:** Always check application-level issues (found via logs) before network/firewall checks — logs give you the root cause **directly and immediately**, while network debugging involves checking multiple layers that take much longer.

---

## Command Reference (commands used throughout this session)

| Command | What it does |
|---|---|
| `docker ps` | Shows running containers |
| `docker ps -a` | Shows all containers (including stopped ones) |
| `docker logs <name>` | Shows a container's logs |
| `docker logs -f <name>` | Live/real-time logs (follow mode) |
| `docker logs --tail 50 <name>` | Only the last 50 lines |
| `docker restart <name>` | Restarts a container |
| `docker exec -it <name> cat <file>` | Views a file's content inside the container |
| `sudo grep -i "<text>" <file>` | Searches for text in a file, case-insensitive |
| `sudo sed -i 's/old/new/' <file>` | Replaces text in a file (in-place) |
| `sudo systemctl restart ssh` | Restarts the SSH service (needed to apply config changes) |
| `sudo ufw status` | Checks the Ubuntu firewall's status |
| `curl -v --max-time 10 <url>` | Sends a request with verbose output and a 10-second timeout |
| `curl localhost/health` | Tests the app's local health-check route |
