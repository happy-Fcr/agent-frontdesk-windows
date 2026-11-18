# Codex and ChatGPT on Windows

Status: existing Codex threads keep using the official app-server queue plus the desktop wake link. New Codex and ChatGPT conversations now use the desktop app's registered `codex://threads/new` protocol with an encoded first prompt and the app's `work` or `chat` mode. The installed app bundle declares the accepted modes as `chat`, `work`, and `codex`. No live prompt was sent while verifying this change.

| Action | Channel | Evidence | Limit |
| --- | --- | --- | --- |
| Read Codex | app-server `thread/read` | existing bridge and native records | complete for local Codex threads |
| Continue Codex | `thread/queue/add` + `codex://threads/wake/<id>` | desktop process takes and runs its official queue | live send not repeated in this change |
| New Codex | `codex://threads/new?prompt=...&mode=work` | route and mode schema in the installed Windows `app.asar` | project/model choices stay in the desktop app |
| New ChatGPT | `codex://threads/new?prompt=...&mode=chat` | same installed route and mode schema | project/attachments are not supported by this link |
| Read/continue ChatGPT cloud chats | none on Windows | cloud bodies are not in local Codex records, and Windows UI automation is intentionally not used for ChatGPT | open the cloud chat in the desktop app |

Resume: use test doubles for URL construction and catalog detection. A real first prompt still needs the user's consent because it spends account quota.
